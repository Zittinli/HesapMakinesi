import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/chat_format.dart';
import '../../core/idle_warning_look.dart';
import '../../core/ticking_builder.dart';
import '../../models/chat_model.dart';
import '../../models/chat_pref_model.dart';
import '../../models/message_model.dart';
import '../../models/moderation_model.dart';
import '../../models/report_model.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/chat_service.dart';
import '../../services/force_lock_service.dart';
import '../../services/moderation_service.dart';
import '../../services/notification_service.dart';
import '../../services/nudge_service.dart';
import '../../services/outgoing_queue_service.dart';
import '../../services/settings_service.dart';
import '../../services/storage_service.dart';
import 'chat_search_screen.dart';
import 'force_lock_button.dart';
import 'group_details_screen.dart';
import 'media_capture_screen.dart';
import 'media_viewer_screen.dart';
import 'message_actions.dart';
import 'message_bubble.dart';
import 'reply_swipe.dart';
import 'typing_bubble.dart';
import 'unread_divider.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.chatId,
    required this.otherUserId,
    required this.otherUserName,
    this.isGroup = false,
    this.groupName,
    this.pendingEmail,
    this.onExitToCalculator,
    this.initialMessageId,
  });

  final String chatId;
  final String otherUserId;
  final String otherUserName;
  final bool isGroup;
  final String? groupName;
  final String? pendingEmail;
  final VoidCallback? onExitToCalculator;
  final String? initialMessageId;

  bool get isPendingOnly =>
      (pendingEmail ?? '').isNotEmpty && otherUserId.isEmpty;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  Timer? _typingDebounce;
  Timer? _readDebounce;
  bool _isSending = false;
  bool _didInitialAlign = false;
  final List<ChatMessage> _pendingOutgoing = [];
  Timer? _idleTimer;
  DateTime? _idleDeadline;
  bool _typingSent = false;
  int? _expireSeconds;
  ChatMessage? _replyTo;
  ChatMessage? _editingMessage;
  List<ChatMessage> _lastMarkedMessages = [];
  List<ChatMessage> _lastRawMessages = [];
  final List<ChatMessage> _olderMessages = [];
  List<String> _lastPurgedIds = [];
  Stream<Map<String, ChatPref>>? _prefsStream;
  Stream<ChatRoom?>? _chatStream;
  Stream<List<ChatMessage>>? _messagesStream;
  Stream<AppUser?>? _otherUserStream;
  ChatService? _chatService;
  SettingsService? _settingsService;
  OutgoingQueueService? _queue;
  bool _queueHooked = false;
  String? _myUid;
  String? _sessionUnreadId;
  String? _highlightedMessageId;
  String? _pendingJumpId;
  bool _initialMessageHandled = false;
  final Map<String, GlobalKey> _messageKeys = {};
  final Map<String, String> _clientKeys = {};
  final Map<String, Future<AppUser?>> _userFutures = {};
  bool _showJumpDown = false;
  final Set<String> _downloadingMediaIds = {};
  final Set<String> _selectedMessageIds = {};
  String? _notice;
  Timer? _noticeTimer;
  bool _loadingOlder = false;
  bool _hasMoreMessages = true;

  static const _ttlOptions = <int?>[null, 10, 60];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final authService = context.read<AuthService>();
    final chatService = context.read<ChatService>();
    _chatService = chatService;
    _settingsService = context.read<SettingsService>();
    final uid = authService.currentUser!.uid;
    _myUid = uid;
    final myEmail = authService.currentUser?.email ?? '';
    _prefsStream ??= chatService.watchChatPrefs(uid);
    if (!_queueHooked) {
      _queueHooked = true;
      _queue = context.read<OutgoingQueueService>();
      _queue!.addListener(_pullQueue);
      _pullQueue();
    }
    if (widget.chatId.isNotEmpty) {
      _chatStream ??= chatService.watchChat(widget.chatId);
    }
    _messagesStream ??= chatService.watchConversationMessages(
      myId: uid,
      myEmail: myEmail,
      chatId: widget.chatId,
      otherId: widget.otherUserId,
      otherEmail: widget.pendingEmail ?? '',
    );
    if (widget.otherUserId.isNotEmpty) {
      _otherUserStream ??= authService.watchUser(widget.otherUserId);
    }
  }

  @override
  void initState() {
    super.initState();
    _messageController.addListener(_onComposerChanged);
    _focusNode.addListener(_onComposerFocus);
    _scrollController.addListener(_onScrollOffset);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bumpIdle();
      if (widget.chatId.isNotEmpty) {
        unawaited(
          context.read<NotificationService>().cancelChat(widget.chatId),
        );
      }
    });
  }

  @override
  void dispose() {
    _queue?.removeListener(_pullQueue);
    _idleTimer?.cancel();
    _typingDebounce?.cancel();
    _readDebounce?.cancel();
    _messageController.removeListener(_onComposerChanged);
    _focusNode.removeListener(_onComposerFocus);
    _messageController.dispose();
    _scrollController.removeListener(_onScrollOffset);
    _scrollController.dispose();
    _focusNode.dispose();
    _noticeTimer?.cancel();
    _setTyping(false);
    super.dispose();
  }

  void _startReply(ChatMessage message) {
    setState(() {
      _replyTo = message;
      _editingMessage = null;
    });
    _focusNode.requestFocus();
  }

  void _onComposerFocus() {
    if (mounted) setState(() {});
    if (_focusNode.hasFocus) {
      _holdIdleWhileTyping();
      return;
    }
    _endTypingAndStartIdle();
  }

  void _onComposerChanged() {
    final hasText = _messageController.text.trim().isNotEmpty;
    _typingDebounce?.cancel();
    if (hasText || _focusNode.hasFocus) {
      if (hasText && !widget.isGroup) {
        _typingSent = true;
        _setTyping(true);
      }
      _holdIdleWhileTyping();
      _typingDebounce = Timer(const Duration(seconds: 2), () {
        if (_typingSent) {
          _typingSent = false;
          _setTyping(false);
        }
        if (!_focusNode.hasFocus) {
          _refreshIdleDeadline();
        }
      });
      return;
    }
    _endTypingAndStartIdle();
  }

  Future<void> _setTyping(bool typing) async {
    if (widget.chatId.isEmpty || widget.isGroup) return;
    final uid = _myUid;
    final chatService = _chatService;
    if (uid == null || chatService == null) return;
    final allowed = _settingsService?.typingEnabled ?? false;
    try {
      await chatService.setTyping(
        chatId: widget.chatId,
        userId: uid,
        typing: typing && allowed,
      );
    } catch (_) {}
  }

  void _holdIdleWhileTyping() {
    _idleDeadline = null;
    if (mounted) setState(() {});
  }

  void _refreshIdleDeadline() {
    final seconds = _settingsService?.chatIdleSeconds ?? 150;
    _idleDeadline = DateTime.now().add(Duration(seconds: seconds));
    if (mounted) setState(() {});
  }

  void _endTypingAndStartIdle() {
    if (_typingSent) {
      _typingSent = false;
      _setTyping(false);
    }
    _refreshIdleDeadline();
  }

  void _bumpIdle() {
    _refreshIdleDeadline();
    _armIdleTimer();
  }

  bool _fastIdleTicks = false;
  bool _idlePausedForRoute = false;

  void _armIdleTimer({bool fast = false}) {
    _fastIdleTicks = fast;
    _idleTimer?.cancel();
    _idleTimer = Timer.periodic(Duration(milliseconds: fast ? 80 : 1000), (_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) {
        _idlePausedForRoute = true;
        return;
      }
      if (_idlePausedForRoute) {
        _idlePausedForRoute = false;
        _refreshIdleDeadline();
        _armIdleTimer();
        return;
      }
      final deadline = _idleDeadline;
      if (deadline == null) return;
      if (DateTime.now().isAfter(deadline)) {
        _idleTimer?.cancel();
        widget.onExitToCalculator?.call();
        return;
      }
      if (IdleWarningLook.progress(deadline) > 0) {
        if (!_fastIdleTicks) _armIdleTimer(fast: true);
        setState(() {});
      }
    });
  }

  double get _idleWarningProgress => IdleWarningLook.progress(_idleDeadline);

  void _showNotice(String text) {
    _noticeTimer?.cancel();
    if (!mounted) return;
    setState(() => _notice = text);
    _noticeTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _notice = null);
    });
  }

  void _dismissNotice() {
    _noticeTimer?.cancel();
    if (_notice == null || !mounted) return;
    setState(() => _notice = null);
  }

  void _pullQueue() {
    if (!mounted) return;
    final queue = _queue;
    if (queue == null) return;
    setState(() {
      _pendingOutgoing
        ..clear()
        ..addAll(
          queue
              .jobsFor(
                chatId: widget.chatId,
                pendingEmail: widget.pendingEmail,
              )
              .map((job) => job.toMessage()),
        );
    });
  }

  Future<void> _sendText() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final currentUser = context.read<AuthService>().currentUser!;
    final queue = context.read<OutgoingQueueService>();
    final moderation = context.read<ModerationService>();
    try {
      await moderation.ensureNotRestricted(
        currentUser.uid,
        currentUser.email ?? '',
      );
    } on AccountRestrictedException catch (error) {
      if (mounted) {
        _showNotice(error.message);
      }
      return;
    }
    if (!mounted) return;

    final editing = _editingMessage;
    if (editing != null) {
      await _saveEdit(editing, text);
      return;
    }
    final reply = _replyTo;
    final ttl = _expireSeconds;
    _messageController.clear();
    if (mounted) {
      setState(() => _replyTo = null);
    }
    _typingSent = false;
    _bumpIdle();
    if (!_showJumpDown) _scrollToBottom();
    await queue.enqueueText(
      senderId: currentUser.uid,
      text: text,
      chatId: widget.chatId,
      pendingEmail: widget.pendingEmail ?? '',
      replyTo: reply,
      expireSeconds: ttl,
    );
  }

  Future<void> _captureMedia() async {
    _holdIdleWhileTyping();
    final captured = await Navigator.of(context).push<CapturedMedia>(
      MaterialPageRoute(builder: (_) => const MediaCaptureScreen()),
    );
    if (captured == null || !mounted) return;
    await _sendMedia(captured);
  }

  Future<void> _pickGalleryMedia() async {
    _holdIdleWhileTyping();
    try {
      final picked = await ImagePicker().pickMultipleMedia();
      if (!mounted || picked.isEmpty) return;
      for (final raw in picked) {
        if (!mounted) return;
        final path = raw.path;
        final isVideo = _galleryFileIsVideo(raw);
        await _sendMedia(
          CapturedMedia(
            file: File(path),
            isVideo: isVideo,
            contentType: isVideo
                ? 'video/mp4'
                : (raw.mimeType ?? 'image/jpeg'),
          ),
          fileName: path.split(Platform.pathSeparator).last,
        );
      }
    } catch (_) {
      if (mounted) {
        _showNotice('Galeri açılamadı.');
      }
    }
  }

  bool _galleryFileIsVideo(XFile file) {
    final path = file.path.toLowerCase();
    final mime = (file.mimeType ?? '').toLowerCase();
    return mime.startsWith('video/') ||
        path.endsWith('.mp4') ||
        path.endsWith('.mov') ||
        path.endsWith('.mkv') ||
        path.endsWith('.webm');
  }

  Future<void> _shareLocation() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      if (mounted) {
        _showNotice('Konum kapalı. Ayarlardan aç.');
      }
      await Geolocator.openLocationSettings();
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) {
        _showNotice('Konum izni yok.');
      }
      return;
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      final link =
          'https://maps.google.com/?q=${pos.latitude},${pos.longitude}';
      _messageController.text = link;
      await _sendText();
    } catch (_) {
      if (mounted) {
        _showNotice('Konum alınamadı.');
      }
    }
  }

  Future<void> _pickAndSendFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        withData: false,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.single;
      final path = picked.path;
      if (path == null || path.isEmpty) {
        if (mounted) {
          _showNotice('Dosya açılamadı.');
        }
        return;
      }
      final file = File(path);
      await _sendMedia(
        CapturedMedia(
          file: file,
          isVideo: false,
          contentType: picked.extension == null
              ? 'application/octet-stream'
              : _mimeFor(picked.extension!, picked.name),
        ),
        fileName: picked.name,
        fileSize: picked.size,
        asFile: true,
      );
    } catch (error) {
      debugPrint('HM_FILE_PICK_FAILED: $error');
      if (mounted) {
        _showNotice('Dosya seçilemedi.');
      }
    }
  }

  String _mimeFor(String ext, String name) {
    final e = ext.toLowerCase();
    if (e == 'pdf') return 'application/pdf';
    if (e == 'txt') return 'text/plain';
    if (e == 'csv') return 'text/csv';
    if (e == 'zip') return 'application/zip';
    if (e == 'doc') return 'application/msword';
    if (e == 'docx') {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (e == 'xls') return 'application/vnd.ms-excel';
    if (e == 'xlsx') {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (e == 'ppt' || e == 'pptx') return 'application/vnd.ms-powerpoint';
    if (e == 'png') return 'image/png';
    if (e == 'jpg' || e == 'jpeg') return 'image/jpeg';
    if (e == 'webp') return 'image/webp';
    if (e == 'mp4') return 'video/mp4';
    if (e == 'mp3') return 'audio/mpeg';
    if (e == 'm4a') return 'audio/mp4';
    if (name.toLowerCase().endsWith('.pdf')) return 'application/pdf';
    return 'application/octet-stream';
  }

  Future<void> _sendMedia(
    CapturedMedia captured, {
    String? fileName,
    int? fileSize,
    bool asFile = false,
  }) async {
    final uid = _myUid!;
    final queue = context.read<OutgoingQueueService>();
    final type = asFile
        ? MessageType.file
        : captured.isVideo
        ? MessageType.video
        : MessageType.image;
    final reply = _replyTo;
    final ttl = _expireSeconds;
    if (mounted) setState(() => _replyTo = null);
    _bumpIdle();
    if (!_showJumpDown) _scrollToBottom();
    await queue.enqueueMedia(
      senderId: uid,
      chatId: widget.chatId,
      file: captured.file,
      type: type,
      contentType: captured.contentType,
      pendingEmail: widget.pendingEmail ?? '',
      replyTo: reply,
      expireSeconds: ttl,
      fileName: fileName,
      fileSize: fileSize,
    );
  }

  Future<void> _showPersonDetails() async {
    AppUser? user;
    if (widget.otherUserId.isNotEmpty) {
      user = await context
          .read<AuthService>()
          .watchUser(widget.otherUserId)
          .first;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF161616),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user?.visibleName ?? widget.otherUserName,
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                ),
                const SizedBox(height: 8),
                Text(
                  'E-posta: ${user?.email.isNotEmpty == true ? user!.email : (widget.pendingEmail ?? '-')}',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 6),
                Text(
                  'Kayıt: ${user?.createdAt == null ? '-' : ChatFormat.eventDateTime(user!.createdAt)}',
                  style: const TextStyle(color: Colors.white54),
                ),
                if (!widget.isGroup &&
                    widget.otherUserId.isNotEmpty &&
                    widget.chatId.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  StreamBuilder<bool>(
                    stream: context.read<ChatService>().watchNudgeAllowed(
                      ownerId: _myUid ?? '',
                      peerId: widget.otherUserId,
                    ),
                    builder: (context, snapshot) {
                      final allowed = snapshot.data == true;
                      return SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: allowed,
                        activeColor: Colors.white70,
                        title: const Text(
                          'Bu kişi beni dürtebilir',
                          style: TextStyle(color: Colors.white70),
                        ),
                        onChanged: (value) {
                          context.read<ChatService>().setNudgeAllow(
                            userId: _myUid ?? '',
                            peerId: widget.otherUserId,
                            chatId: widget.chatId,
                            allow: value,
                          );
                        },
                      );
                    },
                  ),
                  StreamBuilder<bool>(
                    stream: context.read<ChatService>().watchForceLockAllowed(
                      ownerId: _myUid ?? '',
                      peerId: widget.otherUserId,
                    ),
                    builder: (context, snapshot) {
                      final allowed = snapshot.data == true;
                      return SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: allowed,
                        activeColor: Colors.white70,
                        title: const Text(
                          'Beni hesap makinesine gönderebilir',
                          style: TextStyle(color: Colors.white70),
                        ),
                        onChanged: (value) async {
                          try {
                            await context.read<ChatService>().setForceLockAllow(
                              userId: _myUid ?? '',
                              peerId: widget.otherUserId,
                              chatId: widget.chatId,
                              allow: value,
                            );
                          } catch (_) {
                            if (!context.mounted) return;
                            _showNotice(
                              'Anahtar kaydedilemedi. Kuralları yayınlamak gerekebilir.',
                            );
                          }
                        },
                      );
                    },
                  ),
                  StreamBuilder<bool>(
                    stream: context.read<ChatService>().watchForceLockAllowed(
                      ownerId: widget.otherUserId,
                      peerId: _myUid ?? '',
                    ),
                    builder: (context, snapshot) {
                      if (snapshot.data != true) {
                        return const SizedBox.shrink();
                      }
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: ForceLockButton(
                          onPressed: () async {
                            Navigator.pop(context);
                            try {
                              await context.read<ForceLockService>().send(
                                toId: widget.otherUserId,
                                chatId: widget.chatId,
                              );
                            } catch (error) {
                              if (!mounted) return;
                              _showNotice(
                                error.toString().replaceFirst('Bad state: ', ''),
                              );
                            }
                          },
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showGroupDetails() async {
    if (widget.chatId.isEmpty) return;
    final left = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => GroupDetailsScreen(chatId: widget.chatId),
      ),
    );
    if (left == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  bool _canEdit(ChatMessage message) {
    return widget.chatId.isNotEmpty &&
        message.senderId == _myUid &&
        !message.pendingWrite &&
        !message.id.startsWith('local-') &&
        !message.hasMedia &&
        !message.hasFile &&
        !message.deletedForEveryone &&
        !message.isExpired();
  }

  ChatMessage? _loneEditableMessage() {
    final selected = _selectedMessages();
    if (selected.length != 1) return null;
    final message = selected.single;
    return _canEdit(message) ? message : null;
  }

  Future<void> _saveEdit(ChatMessage message, String text) async {
    if (!_canEdit(message) || _isSending) return;
    setState(() => _isSending = true);
    try {
      await context.read<ChatService>().editMessage(
        chatId: widget.chatId,
        messageId: message.id,
        senderId: message.senderId,
        text: text,
      );
      _messageController.clear();
      if (mounted) {
        setState(() => _editingMessage = null);
      }
    } catch (_) {
      if (mounted) {
        _showNotice('Mesaj düzenlenemedi. Tekrar deneyin.');
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _startEdit(ChatMessage message) {
    setState(() {
      _editingMessage = message;
      _replyTo = null;
      _messageController.text = message.text;
      _messageController.selection = TextSelection.fromPosition(
        TextPosition(offset: _messageController.text.length),
      );
    });
    _focusNode.requestFocus();
  }

  void _cancelEdit() {
    setState(() {
      _editingMessage = null;
      _messageController.clear();
    });
  }

  void _onScrollOffset() {
    if (!_scrollController.hasClients) return;
    final away = _scrollController.offset > 120;
    if (away != _showJumpDown && mounted) {
      setState(() => _showJumpDown = away);
    }
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 320) {
      _loadOlderMessages();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(0);
    });
  }

  Future<void> _scrollToFirst() async {
    while (_hasMoreMessages) {
      final loaded = await _loadOlderMessages();
      if (!loaded) break;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  Future<bool> _loadOlderMessages() async {
    if (_loadingOlder || !_hasMoreMessages || _lastRawMessages.isEmpty) {
      return false;
    }
    final before = _lastRawMessages
        .map((message) => message.createdAt)
        .whereType<DateTime>()
        .fold<DateTime?>(null, (oldest, value) {
          if (oldest == null || value.isBefore(oldest)) return value;
          return oldest;
        });
    if (before == null) {
      _hasMoreMessages = false;
      return false;
    }

    setState(() => _loadingOlder = true);
    try {
      final page = await _chatService!.loadOlderConversationMessages(
        myId: _myUid!,
        chatId: widget.chatId,
        otherEmail: widget.pendingEmail ?? '',
        before: before,
      );
      final known = {
        ..._lastRawMessages.map((message) => message.id),
        ..._olderMessages.map((message) => message.id),
      };
      _olderMessages.addAll(
        page.where((message) => !known.contains(message.id)),
      );
      _lastRawMessages = _mergeMessages(const []);
      if (page.length < ChatService.messagePageSize) {
        _hasMoreMessages = false;
      }
      return page.isNotEmpty;
    } catch (error) {
      debugPrint('HM_LOAD_OLDER_FAILED: $error');
      return false;
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  List<ChatMessage> _mergeMessages(List<ChatMessage> recent) {
    final byId = <String, ChatMessage>{
      for (final message in _olderMessages) message.id: message,
      for (final message in _lastRawMessages) message.id: message,
      for (final message in recent) message.id: message,
    };
    final result = byId.values.toList();
    result.sort((a, b) {
      final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return at.compareTo(bt);
    });
    return result;
  }

  Future<void> _jumpToMessage(
    String messageId,
    List<ChatMessage> messages,
  ) async {
    if (messageId.isEmpty) return;
    _pendingJumpId = messageId;
    _showJumpDown = true;

    bool matches(ChatMessage message) =>
        message.id == messageId || message.clientKey == messageId;

    var merged = _mergeMessages(messages);
    var guard = 0;
    while (!merged.any(matches) &&
        _hasMoreMessages &&
        guard < 24) {
      final loaded = await _loadOlderMessages();
      if (!loaded) break;
      merged = _mergeMessages(const []);
      guard += 1;
    }

    if (!merged.any(matches) &&
        widget.chatId.isNotEmpty) {
      final message = await _chatService!.getMessage(
        chatId: widget.chatId,
        messageId: messageId,
      );
      if (message != null &&
          !_olderMessages.any((item) => item.id == message.id)) {
        _olderMessages.add(message);
        if (mounted) setState(() {});
        await WidgetsBinding.instance.endOfFrame;
        merged = _mergeMessages(const []);
      }
    }

    if (!mounted) return;
    final target = merged.cast<ChatMessage?>().firstWhere(
      (message) => message != null && matches(message),
      orElse: () => null,
    );
    if (target == null) {
      _pendingJumpId = null;
      return;
    }

    setState(() => _highlightedMessageId = target.id);
    await _ensureMessageVisible(target.id, merged);
    if (target.clientKey != null && target.clientKey != target.id) {
      await _ensureMessageVisible(target.clientKey!, merged);
    }
    if (mounted) _pendingJumpId = null;
  }

  Future<void> _ensureMessageVisible(
    String messageId,
    List<ChatMessage> messages,
  ) async {
    final reversed = messages.reversed.toList();
    final index = reversed.indexWhere(
      (message) => message.id == messageId || message.clientKey == messageId,
    );
    if (index < 0) return;

    for (var attempt = 0; attempt < 12; attempt++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_scrollController.hasClients) return;
      final targetContext = _messageKeys[messageId]?.currentContext;
      if (targetContext != null && targetContext.mounted) {
        await Scrollable.ensureVisible(
          targetContext,
          alignment: 0.35,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
        );
        return;
      }
      final max = _scrollController.position.maxScrollExtent;
      final estimated = reversed.length <= 1
          ? 0.0
          : max * (index / (reversed.length - 1));
      _scrollController.jumpTo(estimated.clamp(0.0, max));
    }
  }

  Future<void> _markAsRead(List<ChatMessage> messages) async {
    if (widget.chatId.isEmpty) return;
    final currentUserId = context.read<AuthService>().currentUser!.uid;
    final hasUnreadIncoming = messages.any(
      (message) =>
          message.senderId != currentUserId && !message.isReadBy(currentUserId),
    );
    if (!hasUnreadIncoming) return;
    final receipts = context.read<SettingsService>().readReceiptsEnabled;
    await context.read<ChatService>().markMessagesAsRead(
      chatId: widget.chatId,
      readerId: currentUserId,
      messages: messages,
      writeReceipts: receipts,
    );
  }

  void _scheduleMarkAsRead(List<ChatMessage> messages) {
    _readDebounce?.cancel();
    final currentMessages = List<ChatMessage>.from(messages);
    _readDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) unawaited(_markAsRead(currentMessages));
    });
  }

  bool _isSameOutgoing(ChatMessage pending, ChatMessage server) {
    if (server.id.startsWith('local-')) return false;
    if (pending.senderId != server.senderId) return false;
    if (pending.text != server.text) return false;
    if (pending.type != server.type) return false;
    final a = server.createdAt;
    final b = pending.createdAt;
    if (a == null || b == null) return true;
    return a.difference(b).abs() <= const Duration(seconds: 20);
  }

  bool _pendingSyncedBy(ChatMessage pending, List<ChatMessage> server) {
    return server.any(
      (message) => _isSameOutgoing(pending, message) && !message.pendingWrite,
    );
  }

  List<ChatMessage> _withOutgoingDrafts(
    List<ChatMessage> visible,
    List<ChatMessage> drafts,
  ) {
    if (drafts.isEmpty) {
      return [
        for (final message in visible)
          message.copyWith(clientKey: _clientKeys[message.id] ?? message.clientKey),
      ];
    }
    final hiddenIds = <String>{};
    final promoted = <String, ChatMessage>{};
    for (final message in visible) {
      ChatMessage? draft;
      for (final item in drafts) {
        if (_isSameOutgoing(item, message)) {
          draft = item;
          break;
        }
      }
      if (draft == null) continue;
      hiddenIds.add(message.id);
      if (!message.pendingWrite) {
        final key = draft.clientKey ?? draft.id;
        _clientKeys[message.id] = key;
        promoted[draft.id] = message.copyWith(
          pendingWrite: false,
          clientKey: key,
        );
      }
    }
    final result = <ChatMessage>[
      for (final message in visible)
        if (!hiddenIds.contains(message.id))
          message.copyWith(
            clientKey: _clientKeys[message.id] ?? message.clientKey,
          ),
      for (final draft in drafts) promoted[draft.id] ?? draft,
    ];
    result.sort((a, b) {
      final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return at.compareTo(bt);
    });
    return result;
  }

  String? _firstUnreadIdOf(List<ChatMessage> messages, String uid) {
    for (final message in messages) {
      if (message.id.startsWith('local-')) continue;
      if (message.senderId == uid) continue;
      if (!message.readBy.contains(uid)) return message.id;
    }
    return null;
  }

  bool _sameMessages(List<ChatMessage> a, List<ChatMessage> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].text != b[i].text ||
          a[i].readBy.length != b[i].readBy.length ||
          a[i].editedAt != b[i].editedAt ||
          a[i].reactions.length != b[i].reactions.length ||
          a[i].downloadedBy.length != b[i].downloadedBy.length ||
          a[i].pendingWrite != b[i].pendingWrite) {
        return false;
      }
    }
    return true;
  }

  String _presenceText(
    AppUser? user,
    ChatRoom? chat,
    SettingsService settings,
  ) {
    if (chat?.isGroup == true || widget.isGroup) {
      final count = chat?.participants.length;
      return count == null ? '' : '$count katılımcı';
    }
    if (widget.chatId.isEmpty) {
      return 'Çevrimdışı iletilecek';
    }
    if (!settings.lastSeenEnabled) return '';
    if (user == null) return '';
    if (!user.shareLastSeen) return '';
    return ChatFormat.lastSeenLabel(
      user.lastSeen,
      isOnline: user.isEffectivelyOnline(),
    );
  }

  void _cycleTtl() {
    final index = _ttlOptions.indexOf(_expireSeconds);
    setState(
      () => _expireSeconds = _ttlOptions[(index + 1) % _ttlOptions.length],
    );
  }

  String _ttlLabel() {
    if (_expireSeconds == 10) return '10 sn';
    if (_expireSeconds == 60) return '1 dk';
    return 'Süre yok';
  }

  void _exitToCalculator() {
    final exit = widget.onExitToCalculator;
    if (exit != null) {
      exit();
      return;
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _sendNudge() async {
    try {
      await context.read<NudgeService>().send(
        toId: widget.otherUserId,
        chatId: widget.chatId,
      );
    } catch (error) {
      if (!mounted) return;
      _showNotice(error.toString().replaceFirst('Bad state: ', ''));
    }
  }

  Future<void> _onMenuSelected(
    String value,
    ChatPref? pref,
    ChatRoom? chat,
  ) async {
    final auth = context.read<AuthService>();
    final chatService = context.read<ChatService>();
    final uid = auth.currentUser!.uid;

    switch (value) {
      case 'first':
        _scrollToFirst();
      case 'search':
        if (!mounted) return;
        final messageId = await Navigator.of(context).push<String>(
          MaterialPageRoute(
            builder: (_) => ChatSearchScreen(
              messages: _lastMarkedMessages,
              myId: uid,
              chatId: widget.chatId,
            ),
          ),
        );
        if (messageId != null && mounted) {
          _jumpToMessage(messageId, _lastMarkedMessages);
        }
      case 'person':
        await _showPersonDetails();
      case 'group':
        await _showGroupDetails();
      case 'clear':
        final ok = await _confirm(
          'Bu kayıttaki mesajlar sizde temizlensin mi?',
        );
        if (ok == true) {
          await chatService.clearChatForMe(userId: uid, chatId: widget.chatId);
        }
      case 'block':
        final blocked = chat?.blockedBy.contains(uid) == true;
        if (blocked) {
          await chatService.unblockUser(
            userId: uid,
            otherUserId: widget.otherUserId,
            chatId: widget.chatId,
          );
        } else {
          final ok = await _confirm('Bu kişi engellensin mi?');
          if (ok == true) {
            await chatService.blockUser(
              userId: uid,
              otherUserId: widget.otherUserId,
              chatId: widget.chatId,
            );
            if (mounted) Navigator.of(context).pop();
          }
        }
      case 'report_user':
        await _reportUser();
      case 'calculator':
        _exitToCalculator();
    }
  }

  Future<bool?> _confirm(String message) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF161616),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteMessage(
    ChatMessage message, {
    required bool forEveryone,
  }) async {
    if (widget.chatId.isEmpty) {
      if (mounted) {
        _showNotice('Bekleyen mesaj henüz silinemiyor.');
      }
      return;
    }

    final chatService = context.read<ChatService>();
    final uid = context.read<AuthService>().currentUser!.uid;
    try {
      if (forEveryone) {
        await chatService.deleteMessageForEveryone(
          chatId: widget.chatId,
          messageId: message.id,
          senderId: message.senderId,
        );
      } else {
        await chatService.deleteMessageForMe(
          chatId: widget.chatId,
          messageId: message.id,
          userId: uid,
        );
      }
    } catch (_) {
      if (mounted) {
        _showNotice('Mesaj silinemedi. Tekrar deneyin.');
      }
    }
  }

  bool _canSelect(ChatMessage message) {
    return widget.chatId.isNotEmpty &&
        message.id.isNotEmpty &&
        !message.pendingWrite &&
        !message.id.startsWith('local-');
  }

  void _toggleMessageSelection(ChatMessage message) {
    if (!_canSelect(message)) return;
    setState(() {
      if (!_selectedMessageIds.add(message.id)) {
        _selectedMessageIds.remove(message.id);
      }
    });
  }

  void _clearMessageSelection() {
    if (_selectedMessageIds.isEmpty) return;
    setState(() => _selectedMessageIds.clear());
  }

  List<ChatMessage> _selectedMessages() {
    final byId = <String, ChatMessage>{
      for (final message in _lastMarkedMessages) message.id: message,
    };
    final selected = [
      for (final id in _selectedMessageIds)
        if (byId[id] != null) byId[id]!,
    ];
    selected.sort((a, b) {
      final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final order = at.compareTo(bt);
      if (order != 0) return order;
      return a.id.compareTo(b.id);
    });
    return selected;
  }

  Future<void> _copySelectedMessages() async {
    final parts = <String>[];
    for (final message in _selectedMessages()) {
      final body = message.text.trim().isNotEmpty
          ? message.text.trim()
          : message.preview.trim();
      if (body.isEmpty) continue;
      parts.add(body);
    }
    if (parts.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: parts.join('\n\n')));
    if (!mounted) return;
    _clearMessageSelection();
    _showNotice('Mesajlar kopyalandı.');
  }

  Future<void> _deleteSelectedMessages() async {
    final targets = _selectedMessages();
    if (targets.isEmpty) return;
    final ok = await _confirm(
      targets.length == 1
          ? 'Bu mesaj senden silinsin mi?'
          : '${targets.length} mesaj senden silinsin mi?',
    );
    if (ok != true || !mounted) return;
    for (final message in targets) {
      await _deleteMessage(message, forEveryone: false);
    }
    if (mounted) _clearMessageSelection();
  }

  Future<ReportReason?> _askReportReason() {
    return showModalBottomSheet<ReportReason>(
      context: context,
      backgroundColor: const Color(0xFF161616),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Neden bildiriyorsunuz?',
                  style: TextStyle(color: Colors.white70, fontSize: 15),
                ),
              ),
              ...ReportReason.values.map(
                (item) => ListTile(
                  title: Text(
                    item.label,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  onTap: () => Navigator.pop(context, item),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _reportMessage(ChatMessage message) async {
    final reason = await _askReportReason();
    if (reason == null || !mounted) return;
    await _sendReport(
      () => context.read<ModerationService>().reportMessage(
        message: message,
        chatId: widget.chatId,
        reportedUserId: message.senderId,
        reportedEmail: widget.otherUserName,
        reason: reason,
      ),
    );
  }

  Future<void> _reportUser() async {
    if (widget.chatId.isEmpty || widget.otherUserId.isEmpty) {
      _showNotice('Bu kayıt henüz aktif değil, kişi bildirilemez.');
      return;
    }

    final reason = await _askReportReason();
    if (reason == null || !mounted) return;
    await _sendReport(
      () => context.read<ModerationService>().reportUser(
        chatId: widget.chatId,
        reportedUserId: widget.otherUserId,
        reportedEmail: widget.otherUserName,
        reason: reason,
      ),
    );
  }

  Future<void> _sendReport(Future<void> Function() send) async {
    try {
      await send();
      if (!mounted) return;
      _showNotice('Bildirim gönderildi.');
    } catch (_) {
      if (!mounted) return;
      _showNotice('Bildirim gönderilemedi. Tekrar deneyin.');
    }
  }

  Future<AppUser?> _userFor(String userId) {
    if (userId.isEmpty) return Future.value(null);
    return _userFutures.putIfAbsent(
      userId,
      () => context.read<AuthService>().watchUser(userId).first,
    );
  }

  Future<void> _showMessageDetails(ChatMessage message) async {
    final viewerIds = message.readBy
        .where((id) => id != message.senderId)
        .toSet()
        .toList();
    final viewers = await Future.wait(viewerIds.map(_userFor));
    if (!mounted) return;
    final sender = await _userFor(message.senderId);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF161616),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Mesaj ayrıntıları',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
              const SizedBox(height: 12),
              Text(
                'Gönderen: ${sender?.visibleName ?? message.senderId}',
                style: const TextStyle(color: Colors.white70),
              ),
              Text(
                'Gönderilme: ${message.createdAt == null ? '-' : ChatFormat.eventDateTime(message.createdAt)}',
                style: const TextStyle(color: Colors.white54),
              ),
              const SizedBox(height: 16),
              const Text(
                'Gören kişiler',
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              if (viewers.isEmpty)
                const Text(
                  'Henüz okundu bilgisi yok.',
                  style: TextStyle(color: Colors.white38),
                )
              else
                ...List.generate(viewers.length, (index) {
                  final user = viewers[index];
                  final seenAt = message.readAt[viewerIds[index]];
                  final name = user?.visibleName ?? 'Bilinmeyen kullanıcı';
                  final when = seenAt == null
                      ? 'saat yok (eski okuma)'
                      : ChatFormat.eventDateTime(seenAt);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(
                      '$name · $when',
                      style: const TextStyle(color: Colors.white54),
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _removeMessageSender(ChatRoom chat, ChatMessage message) async {
    final sender = await _userFor(message.senderId);
    if (!mounted) return;
    final confirmed = await _confirm(
      '${sender?.visibleName ?? 'Bu kullanıcı'} gruptan çıkarılsın mı?',
    );
    if (confirmed != true || !mounted) return;
    try {
      await context.read<ChatService>().removeMember(
        chatId: chat.id,
        memberId: message.senderId,
      );
      if (mounted) {
        _showNotice('Kullanıcı gruptan çıkarıldı.');
      }
    } catch (error) {
      if (mounted) {
        _showNotice('$error');
      }
    }
  }

  Future<void> _react(ChatMessage message, String emoji) async {
    if (widget.chatId.isEmpty || message.id.startsWith('local-')) return;
    final uid = _myUid;
    if (uid == null) return;
    try {
      await _chatService?.setReaction(
        chatId: widget.chatId,
        messageId: message.id,
        userId: uid,
        emoji: emoji,
        current: message.reactions,
      );
    } catch (error) {
      debugPrint('HM_REACT_FAILED: $error');
    }
  }

  Future<void> _showMessageMenu(
    ChatMessage message,
    bool isMine,
    ChatRoom? chat,
    BuildContext anchorContext,
  ) async {
    if (!anchorContext.mounted) return;

    final selected = await showMessageActions(
      context: context,
      anchorContext: anchorContext,
      isMine: isMine,
      quickEmojis: context.read<SettingsService>().favoriteEmojis,
      entries: [
        if (!message.hasMedia && !message.hasFile)
          const MessageMenuEntry('copy', 'Kopyala'),
        if (message.hasMedia || message.hasFile)
          const MessageMenuEntry('download', 'İndir'),
        const MessageMenuEntry('reply', 'Yanıtla'),
        if (widget.chatId.isNotEmpty)
          const MessageMenuEntry('details', 'Ayrıntı'),
        if (_canEdit(message))
          const MessageMenuEntry('edit', 'Düzenle'),
        const MessageMenuEntry('delete_me', 'Benden sil'),
        if (!isMine && widget.chatId.isNotEmpty)
          const MessageMenuEntry('report', 'Bildir', color: Color(0xFFFFCC80)),
        if (!isMine &&
            chat?.isGroup == true &&
            chat!.isAdmin(_myUid ?? '') &&
            !chat.isAdmin(message.senderId))
          const MessageMenuEntry(
            'kick',
            'Gruptan çıkar',
            color: Color(0xFFFF8A80),
          ),
        if (isMine)
          const MessageMenuEntry(
            'delete_all',
            'Herkesten sil',
            color: Color(0xFFFF8A80),
          ),
      ],
    );
    if (!mounted || selected == null) return;
    if (selected == 'edit-quick') {
      await _editQuickEmojis();
      return;
    }
    if (selected.startsWith('react:')) {
      await _react(message, selected.substring('react:'.length));
      return;
    }
    switch (selected) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: message.text));
      case 'download':
        await _downloadMedia(message);
      case 'reply':
        _startReply(message);
      case 'details':
        await _showMessageDetails(message);
      case 'edit':
        _startEdit(message);
      case 'delete_me':
        final deleteMine = await _confirm('Bu mesaj senden silinsin mi?');
        if (deleteMine == true && mounted) {
          await _deleteMessage(message, forEveryone: false);
        }
      case 'report':
        await _reportMessage(message);
      case 'kick':
        final room = chat;
        if (room != null) await _removeMessageSender(room, message);
      case 'delete_all':
        final deleteAll = await _confirm('Bu mesaj herkesten silinsin mi?');
        if (deleteAll == true && mounted) {
          await _deleteMessage(message, forEveryone: true);
        }
    }
  }

  Future<void> _editQuickEmojis() async {
    final settings = context.read<SettingsService>();
    final auth = context.read<AuthService>();
    await showQuickEmojiEditor(
      context: context,
      selected: settings.favoriteEmojis,
      onSave: (emojis) async {
        settings.keepLocalQuickEmojis();
        await settings.setFavoriteEmojis(emojis);
        try {
          await auth.saveQuickEmojis(settings.favoriteEmojis);
        } catch (error) {
          settings.keepLocalQuickEmojis();
          rethrow;
        }
      },
    );
  }

  String? _cachedMediaPath(ChatMessage message, SettingsService settings) {
    final keys = <String>[
      if (message.isLocalMediaFile) message.mediaUrl ?? '',
      message.id,
      message.clientKey ?? '',
      message.mediaUrl ?? '',
    ];
    for (final key in keys) {
      if (key.isEmpty) continue;
      if (message.isLocalMediaFile && key == message.mediaUrl) {
        if (File(key).existsSync()) return key;
        continue;
      }
      final path = settings.mediaFilePath(key);
      if (path != null && File(path).existsSync()) return path;
    }
    return null;
  }

  Future<void> _openMedia(ChatMessage message) async {
    final url = message.mediaUrl;
    if (url == null || url.isEmpty) return;
    if (message.hasFile) {
      await _downloadMedia(message);
      return;
    }
    final settings = context.read<SettingsService>();
    final local = _cachedMediaPath(message, settings);
    final uid = _myUid;
    final mine = message.senderId == uid;
    final downloaded = settings.isMediaDownloaded(message.id) ||
        (uid != null && message.downloadedBy.contains(uid));
    if (local == null && !mine && !downloaded) {
      await _downloadMedia(message);
      return;
    }
    if (local == null && !message.isHttpMedia) {
      await _downloadMedia(message);
      if (!mounted) return;
      final cached = _cachedMediaPath(message, context.read<SettingsService>());
      if (cached == null) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MediaViewerScreen(
            url: url,
            file: File(cached),
            isVideo: message.type == MessageType.video,
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MediaViewerScreen(
          url: url,
          file: local == null ? null : File(local),
          isVideo: message.type == MessageType.video,
        ),
      ),
    );
  }

  Future<void> _downloadMedia(ChatMessage message) async {
    final url = message.mediaUrl;
    if (url == null || url.isEmpty) return;
    final messageId = message.id;
    if (messageId.isNotEmpty && mounted) {
      setState(() => _downloadingMediaIds.add(messageId));
    }
    final storage = context.read<StorageService>();
    final settings = context.read<SettingsService>();
    try {
      var cached = _cachedMediaPath(message, settings);
      if (cached == null && !message.isLocalMediaFile) {
        final file = message.hasFile
            ? await storage.downloadToDocuments(
                locator: url,
                fileName: message.fileName ?? 'dosya',
              )
            : await storage.downloadToCache(
                locator: url,
                messageId: messageId.isEmpty
                    ? '${DateTime.now().millisecondsSinceEpoch}'
                    : messageId,
                fileName: message.fileName,
              );
        cached = file.path;
        await settings.rememberMediaFile(
          [messageId, message.clientKey ?? '', url],
          cached,
        );
      }
      if (cached == null) {
        throw const FileSystemException('Medya dosyası yok.');
      }
      if (message.hasFile) {
        if (!mounted) return;
        await _rememberDownload(message);
        if (!mounted) return;
        _showNotice('İndirildi: $cached');
        return;
      }
      await storage.saveToGallery(
        File(cached),
        isVideo: message.type == MessageType.video,
      );
      if (!mounted) return;
      await _rememberDownload(message);
      if (!mounted) return;
      _showNotice('Galeriye indirildi.');
    } catch (_) {
      if (!mounted) return;
      _showNotice('Medya indirilemedi.');
    } finally {
      if (mounted && messageId.isNotEmpty) {
        setState(() => _downloadingMediaIds.remove(messageId));
      }
    }
  }

  Future<void> _rememberDownload(ChatMessage message) async {
    await context.read<SettingsService>().markMediaDownloaded(message.id);
    final uid = _myUid;
    if (uid == null || widget.chatId.isEmpty) return;
    try {
      await context.read<ChatService>().markMessageDownloaded(
        chatId: widget.chatId,
        messageId: message.id,
        userId: uid,
      );
    } catch (_) {}
  }

  PopupMenuItem<String> _menuItem(
    String value,
    String label, {
    bool warn = false,
    bool danger = false,
  }) {
    final color = danger
        ? const Color(0xFFFF8A80)
        : warn
        ? const Color(0xFFFFCC80)
        : Colors.white;
    return PopupMenuItem(
      value: value,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.enter &&
        event.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    final shift =
        HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.shiftLeft,
        ) ||
        HardwareKeyboard.instance.logicalKeysPressed.contains(
          LogicalKeyboardKey.shiftRight,
        );
    if (shift) return KeyEventResult.ignored;
    _sendText();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.read<AuthService>();
    final chatService = context.read<ChatService>();
    final settings = context.watch<SettingsService>();
    final currentUserId = authService.currentUser!.uid;
    if (!settings.typingEnabled && _typingSent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_typingSent) return;
        _typingSent = false;
        _setTyping(false);
      });
    }

    return StreamBuilder<Map<String, ChatPref>>(
      stream: _prefsStream,
      builder: (context, prefSnapshot) {
        final pref = prefSnapshot.data?[widget.chatId];

        return StreamBuilder<ChatRoom?>(
          stream: _chatStream,
          builder: (context, chatSnapshot) {
            final chat = chatSnapshot.data;
            final isGroup = chat?.isGroup ?? widget.isGroup;
            final title = isGroup
                ? ((chat?.groupName.trim().isNotEmpty == true)
                      ? chat!.groupName
                      : (widget.groupName ?? widget.otherUserName))
                : widget.otherUserName;
            final blocked = !isGroup && chat?.isBlocked() == true;

            final warning = _idleWarningProgress;
            final selecting = _selectedMessageIds.isNotEmpty;
            return PopScope(
              canPop: !selecting,
              onPopInvokedWithResult: (didPop, _) {
                if (didPop) return;
                _clearMessageSelection();
              },
              child: Scaffold(
              backgroundColor: IdleWarningLook.scaffold(warning),
              floatingActionButton: null,
              appBar: AppBar(
                backgroundColor: IdleWarningLook.appBar(warning),
                foregroundColor: Colors.white70,
                elevation: 0,
                automaticallyImplyLeading: !selecting,
                leading: selecting
                    ? IconButton(
                        tooltip: 'Seçimi kapat',
                        onPressed: _clearMessageSelection,
                        icon: const Icon(Icons.close),
                      )
                    : null,
                title: selecting
                    ? Text(
                        '${_selectedMessageIds.length} seçildi',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      )
                    : StreamBuilder<AppUser?>(
                  stream: isGroup ? null : _otherUserStream,
                  builder: (context, snapshot) {
                    final user = snapshot.data;
                    return GestureDetector(
                      onLongPress: isGroup
                          ? _showGroupDetails
                          : _showPersonDetails,
                      onTap: isGroup ? _showGroupDetails : _showPersonDetails,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOut,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: IdleWarningLook.nameWash(warning),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              isGroup
                                  ? title
                                  : (user?.visibleName ?? title),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: TickingBuilder(
                            interval: const Duration(seconds: 2),
                            builder: (_) {
                              final text = _presenceText(user, chat, settings);
                              final typing = text == 'Yazıyor...';
                              if (text.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              return Text(
                                text,
                                style: TextStyle(
                                  color: typing
                                      ? const Color(0xFF90CAF9)
                                      : Colors.white54,
                                  fontSize: 12,
                                  fontStyle: typing
                                      ? FontStyle.italic
                                      : FontStyle.normal,
                                ),
                              );
                            },
                          ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                actions: selecting
                    ? [
                        if (_loneEditableMessage() != null)
                          IconButton(
                            tooltip: 'Düzenle',
                            onPressed: () {
                              final message = _loneEditableMessage();
                              if (message == null) return;
                              _clearMessageSelection();
                              _startEdit(message);
                            },
                            icon: const Icon(Icons.edit_outlined, size: 20),
                          ),
                        IconButton(
                          tooltip: 'Kopyala',
                          onPressed: _copySelectedMessages,
                          icon: const Icon(Icons.copy, size: 20),
                        ),
                        IconButton(
                          tooltip: 'Benden sil',
                          onPressed: _deleteSelectedMessages,
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ]
                    : [
                  if (!isGroup &&
                      widget.otherUserId.isNotEmpty &&
                      widget.chatId.isNotEmpty)
                    StreamBuilder<bool>(
                      stream: context.read<ChatService>().watchNudgeAllowed(
                        ownerId: widget.otherUserId,
                        peerId: currentUserId,
                      ),
                      builder: (context, snapshot) {
                        if (snapshot.data != true) {
                          return const SizedBox.shrink();
                        }
                        return IconButton(
                          tooltip: 'Dürt',
                          icon: const Icon(Icons.vibration),
                          onPressed: _sendNudge,
                        );
                      },
                    ),
                  IconButton(
                    tooltip: 'Hesap makinesine dön',
                    icon: const Icon(Icons.calculate_outlined),
                    onPressed: _exitToCalculator,
                  ),
                  PopupMenuButton<String>(
                    color: const Color(0xFF161616),
                    icon: const Icon(Icons.more_vert, size: 22),
                    padding: EdgeInsets.zero,
                    menuPadding: const EdgeInsets.symmetric(vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                    ),
                    onSelected: (value) => _onMenuSelected(value, pref, chat),
                    itemBuilder: (context) => [
                      _menuItem('search', 'Bu sohbette ara'),
                      _menuItem('first', 'İlk mesaja git'),
                      if (!isGroup) _menuItem('person', 'Kişi ayrıntısı'),
                      if (isGroup) _menuItem('group', 'Grup ayrıntıları'),
                      _menuItem('clear', 'Sohbeti temizle'),
                      if (!isGroup)
                        _menuItem(
                          'block',
                          chat?.blockedBy.contains(currentUserId) == true
                              ? 'Engeli kaldır'
                              : 'Kişiyi engelle',
                        ),
                      if (!isGroup)
                        _menuItem('report_user', 'Kişiyi bildir', warn: true),
                      _menuItem('calculator', 'Hesap makinesine dön'),
                    ],
                  ),
                ],
              ),
              body: Column(
                children: [
                  if (blocked)
                    Container(
                      width: double.infinity,
                      color: const Color(0xFF2A1A1A),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: const Text(
                        'Bu yazışma engellenmiş. Yeni mesaj gönderilemez.',
                        style: TextStyle(
                          color: Color(0xFFFF8A80),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  if (chat?.isGroupTimedOut() == true)
                    Container(
                      width: double.infinity,
                      color: const Color(0xFF2A2418),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Text(
                        'Bu grup ${ChatFormat.eventDateTime(chat!.groupTimeoutUntil)} tarihine kadar askıda.',
                        style: const TextStyle(
                          color: Color(0xFFFFCC80),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  Expanded(
                    child: Stack(
                      children: [
                        StreamBuilder<List<ChatMessage>>(
                      stream: _messagesStream,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                                ConnectionState.waiting &&
                            !snapshot.hasData &&
                            _lastMarkedMessages.isEmpty) {
                          return const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white24,
                            ),
                          );
                        }

                        if (snapshot.hasError &&
                            !snapshot.hasData &&
                            _lastMarkedMessages.isEmpty) {
                          return const Center(
                            child: Text(
                              'Mesajlar yüklenemedi.',
                              style: TextStyle(color: Colors.white38),
                            ),
                          );
                        }

                        final recent = snapshot.data ?? const <ChatMessage>[];
                        final raw = _mergeMessages(recent);
                        _lastRawMessages = raw;
                        if (recent.isNotEmpty &&
                            recent.length < ChatService.messagePageSize &&
                            _olderMessages.isEmpty) {
                          _hasMoreMessages = false;
                        }
                        final expiredIds = raw
                            .where((m) => m.isExpired())
                            .map((m) => m.id)
                            .toList();
                        if (widget.chatId.isNotEmpty &&
                            expiredIds.isNotEmpty &&
                            expiredIds.join() != _lastPurgedIds.join()) {
                          _lastPurgedIds = expiredIds;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            chatService.purgeExpiredMessages(
                              chatId: widget.chatId,
                              messages: raw,
                            );
                          });
                        }

                        final visible = raw
                            .where(
                              (m) => m.isVisibleTo(
                                currentUserId,
                                clearedAt: pref?.clearedAt,
                              ),
                            )
                            .toList();
                        final pending = List<ChatMessage>.from(_pendingOutgoing);
                        final messages = _withOutgoingDrafts(visible, pending);
                        final ownUploaded = <String>[
                          for (final message in visible)
                            if (message.senderId == currentUserId &&
                                (message.hasMedia || message.hasFile) &&
                                (message.isHttpMedia ||
                                    message.isStoragePath) &&
                                !settings.isMediaUploaded(message.id))
                              message.id,
                        ];
                        if (ownUploaded.isNotEmpty ||
                            _pendingOutgoing.any(
                              (item) => _pendingSyncedBy(item, visible),
                            )) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            final uploadedIds = [...ownUploaded];
                            for (final draft in _pendingOutgoing) {
                              if (!_pendingSyncedBy(draft, visible)) continue;
                              unawaited(_queue?.complete(draft.id));
                              if (!draft.hasMedia && !draft.hasFile) continue;
                              uploadedIds.add(draft.id);
                              for (final message in visible) {
                                if (_isSameOutgoing(draft, message) &&
                                    !message.pendingWrite) {
                                  uploadedIds.add(message.id);
                                }
                              }
                            }
                            if (uploadedIds.isNotEmpty) {
                              unawaited(
                                context.read<SettingsService>().markMediaUploaded(
                                  uploadedIds,
                                ),
                              );
                            }
                          });
                        }

                        if (!_initialMessageHandled &&
                            (widget.initialMessageId ?? '').isNotEmpty &&
                            messages.isNotEmpty) {
                          _initialMessageHandled = true;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            _jumpToMessage(widget.initialMessageId!, messages);
                          });
                        }

                        if (messages.isNotEmpty && _sessionUnreadId == null && !_didInitialAlign) {
                          _sessionUnreadId = _firstUnreadIdOf(
                            messages,
                            currentUserId,
                          );
                        }

                        if (messages.length != _lastMarkedMessages.length ||
                            !_sameMessages(messages, _lastMarkedMessages)) {
                          _lastMarkedMessages = List<ChatMessage>.from(
                            messages,
                          );
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _scheduleMarkAsRead(messages);
                          });
                          if (!_didInitialAlign &&
                              widget.initialMessageId == null) {
                            _didInitialAlign = true;
                            final unreadId = _firstUnreadIdOf(
                              messages,
                              currentUserId,
                            );
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!mounted) return;
                              if (unreadId != null) {
                                _showJumpDown = true;
                                _jumpToMessage(unreadId, messages);
                              } else {
                                _scrollToBottom();
                              }
                            });
                          } else if (!_showJumpDown && _pendingJumpId == null) {
                            _scrollToBottom();
                          }
                        }

                        if (messages.isEmpty) {
                          return const Center(
                            child: Text(
                              'İlk mesajı yazın.',
                              style: TextStyle(color: Colors.white38),
                            ),
                          );
                        }

                        final reversed = messages.reversed.toList();
                        return ListView.builder(
                          controller: _scrollController,
                          reverse: true,
                          cacheExtent: _pendingJumpId == null ? 400 : 12000,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          itemCount:
                              reversed.length +
                              ((_hasMoreMessages || _loadingOlder) ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == reversed.length) {
                              return Padding(
                                padding: const EdgeInsets.all(12),
                                child: Center(
                                  child: _loadingOlder
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white24,
                                          ),
                                        )
                                      : TextButton(
                                          onPressed: _loadOlderMessages,
                                          child: const Text(
                                            'Daha eski mesajları yükle',
                                          ),
                                        ),
                                ),
                              );
                            }
                            final message = reversed[index];
                            final older = index == reversed.length - 1
                                ? null
                                : reversed[index + 1];
                            final showDay = !ChatFormat.isSameDay(
                              older?.createdAt,
                              message.createdAt,
                            );
                            final isMine = message.senderId == currentUserId;
                            final isRead =
                                settings.readReceiptsEnabled &&
                                message.readBy.any((id) => id != currentUserId);
                            final firstUnreadId = _sessionUnreadId;

            final bubbleKey = message.clientKey ?? message.id;
            final messageKey = _messageKeys.putIfAbsent(
              bubbleKey,
              () => GlobalKey(),
            );
            _messageKeys[message.id] = messageKey;
                            return Column(
                              key: messageKey,
                              children: [
                                if (showDay && message.createdAt != null)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    child: Text(
                                      ChatFormat.dayLabel(message.createdAt!),
                                      style: const TextStyle(
                                        color: Colors.white30,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                if (message.id == firstUnreadId)
                                  const UnreadDivider(),
                                FutureBuilder<AppUser?>(
                                  future: isGroup && !isMine
                                      ? _userFor(message.senderId)
                                      : null,
                                  builder: (context, senderSnapshot) {
                                    final selecting =
                                        _selectedMessageIds.isNotEmpty;
                                    final selected = _selectedMessageIds
                                        .contains(message.id);
                                    return ReplySwipe(
                                      onReply: selecting
                                          ? () {}
                                          : () => _startReply(message),
                                      onMenu: selecting
                                          ? () {}
                                          : () => _showMessageMenu(
                                              message,
                                              isMine,
                                              chat,
                                              context,
                                            ),
                                      child: Row(
                                        children: [
                                          if (selecting)
                                            GestureDetector(
                                              onTap: () =>
                                                  _toggleMessageSelection(
                                                    message,
                                                  ),
                                              child: Padding(
                                                padding: const EdgeInsets.only(
                                                  left: 10,
                                                  right: 2,
                                                ),
                                                child: Icon(
                                                  selected
                                                      ? Icons.check_circle
                                                      : Icons.circle_outlined,
                                                  size: 22,
                                                  color: selected
                                                      ? const Color(0xFF90CAF9)
                                                      : Colors.white38,
                                                ),
                                              ),
                                            ),
                                          Expanded(
                                            child: RepaintBoundary(
                                              child: MessageBubble(
                                                message: message,
                                                isMine: isMine,
                                                isRead: isRead,
                                                pending: message.pendingWrite,
                                                selected: selected,
                                                localPath: _cachedMediaPath(
                                                  message,
                                                  settings,
                                                ),
                                                downloading:
                                                    _downloadingMediaIds
                                                        .contains(message.id),
                                                downloaded: settings
                                                    .isMediaDownloaded(
                                                      message.id,
                                                    ),
                                                senderLabel: isGroup && !isMine
                                                    ? (senderSnapshot
                                                              .data
                                                              ?.visibleName ??
                                                          'Grup üyesi')
                                                    : null,
                                                highlighted:
                                                    message.id ==
                                                    _highlightedMessageId,
                                                onLongPress: () =>
                                                    _toggleMessageSelection(
                                                      message,
                                                    ),
                                                onTap: selecting
                                                    ? () =>
                                                          _toggleMessageSelection(
                                                            message,
                                                          )
                                                    : null,
                                                onMediaTap: () =>
                                                    _openMedia(message),
                                                onReplyTap:
                                                    (message.replyToId ?? '')
                                                        .isEmpty
                                                    ? null
                                                    : () => _jumpToMessage(
                                                        message.replyToId!,
                                                        messages,
                                                      ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                        if (_showJumpDown)
                          Positioned(
                            right: 10,
                            bottom: 10,
                            child: FloatingActionButton.small(
                              backgroundColor: const Color(0xFF2A2A2A),
                              foregroundColor: Colors.white70,
                              onPressed: _scrollToBottom,
                              child: const Icon(Icons.arrow_downward, size: 18),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_notice != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                      child: GestureDetector(
                        onTap: _dismissNotice,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xFF161616),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFF2C2C2C)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            child: Text(
                              _notice!,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_editingMessage != null)
                    Container(
                      width: double.infinity,
                      color: const Color(0xFF161616),
                      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.edit_outlined,
                            color: Colors.white38,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Mesajı düzenle',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: _cancelEdit,
                            icon: const Icon(
                              Icons.close,
                              color: Colors.white38,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_replyTo != null)
                    Container(
                      width: double.infinity,
                      color: const Color(0xFF161616),
                      padding: const EdgeInsets.fromLTRB(12, 6, 0, 6),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.reply,
                            color: Colors.white38,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _replyTo!.preview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            onPressed: () => setState(() => _replyTo = null),
                            icon: const Icon(
                              Icons.close,
                              color: Colors.white38,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 4, 4, 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          TickingBuilder(
                            interval: const Duration(seconds: 2),
                            builder: (_) {
                              final keyboardOpen =
                                  MediaQuery.viewInsetsOf(context).bottom >= 80;
                              final typing = !isGroup &&
                                  settings.typingEnabled &&
                                  chat != null &&
                                  chat.isOtherTyping(widget.otherUserId);
                              return Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  _AttachFlyoutButton(
                                    enabled: !blocked,
                                    collapsed: keyboardOpen,
                                    showTyping: typing && !keyboardOpen,
                                    onPickFile: _pickAndSendFile,
                                    onPickGallery: _pickGalleryMedia,
                                    onShareLocation: _shareLocation,
                                  ),
                                  if (!keyboardOpen) const SizedBox(width: 6),
                                  Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      IconButton(
                                        tooltip: 'Fotoğraf / video',
                                        padding: EdgeInsets.zero,
                                        visualDensity: VisualDensity.compact,
                                        constraints: _composerIconConstraints,
                                        style: _composerIconStyle,
                                        color: Colors.white70,
                                        onPressed:
                                            blocked ? null : _captureMedia,
                                        icon: const Icon(
                                          Icons.photo_camera_outlined,
                                          size: 26,
                                        ),
                                      ),
                                      if (typing && keyboardOpen)
                                        const Positioned(
                                          right: -4,
                                          top: -5,
                                          child: IgnorePointer(
                                            child: TypingBubble(),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            tooltip: _ttlLabel(),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            constraints: _composerIconConstraints,
                            style: _composerIconStyle,
                            color: _expireSeconds == null
                                ? Colors.white38
                                : const Color(0xFFFFCC80),
                            onPressed: blocked ? null : _cycleTtl,
                            icon: Icon(
                              _expireSeconds == null
                                  ? Icons.timer_off_outlined
                                  : Icons.timer_outlined,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Focus(
                              onKeyEvent: _onKey,
                              child: TextField(
                                controller: _messageController,
                                focusNode: _focusNode,
                                enabled: !blocked,
                                minLines: 1,
                                maxLines: 8,
                                keyboardType: TextInputType.multiline,
                                textCapitalization: TextCapitalization.sentences,
                                style: const TextStyle(color: Colors.white, fontSize: 15),
                                cursorColor: Colors.white54,
                                decoration: InputDecoration(
                                  hintText: blocked
                                      ? 'Engellendi'
                                      : (_editingMessage != null
                                            ? 'Mesajı düzenle...'
                                            : 'Yazı...'),
                                  hintStyle: const TextStyle(
                                    color: Colors.white30,
                                  ),
                                  filled: true,
                                  fillColor: const Color(0xFF1A1A1A),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 10,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide.none,
                                  ),
                                  isDense: true,
                                  suffixText: _expireSeconds == null
                                      ? null
                                      : _ttlLabel(),
                                  suffixStyle: const TextStyle(
                                    color: Color(0xFFFFCC80),
                                    fontSize: 11,
                                  ),
                                ),
                                textInputAction: TextInputAction.newline,
                              ),
                            ),
                          ),
                          IconButton(
                            color: Colors.white70,
                            onPressed: blocked ? null : _sendText,
                            icon: const Icon(Icons.arrow_upward),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            );
          },
        );
      },
    );
  }
}

const _composerIconConstraints = BoxConstraints.tightFor(width: 44, height: 44);

final _composerIconStyle = IconButton.styleFrom(
  padding: EdgeInsets.zero,
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  minimumSize: const Size(44, 44),
  maximumSize: const Size(44, 44),
  visualDensity: VisualDensity.compact,
);

class _AttachFlyoutButton extends StatefulWidget {
  const _AttachFlyoutButton({
    required this.enabled,
    required this.onPickFile,
    required this.onPickGallery,
    required this.onShareLocation,
    this.showTyping = false,
    this.collapsed = false,
  });

  final bool enabled;
  final bool showTyping;
  final bool collapsed;
  final VoidCallback onPickFile;
  final VoidCallback onPickGallery;
  final VoidCallback onShareLocation;

  @override
  State<_AttachFlyoutButton> createState() => _AttachFlyoutButtonState();
}

class _AttachFlyoutButtonState extends State<_AttachFlyoutButton>
    with SingleTickerProviderStateMixin {
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  late final AnimationController _anim;
  late final CurvedAnimation _motion;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      reverseDuration: const Duration(milliseconds: 120),
    );
    _motion = CurvedAnimation(
      parent: _anim,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.35),
      end: Offset.zero,
    ).animate(_motion);
  }

  @override
  void dispose() {
    if (_portal.isShowing) _portal.hide();
    _motion.dispose();
    _anim.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (!widget.enabled || widget.collapsed) return;
    if (_portal.isShowing) {
      await _anim.reverse();
      if (mounted) _portal.hide();
      return;
    }
    _portal.show();
    await _anim.forward(from: 0);
  }

  Future<void> _run(VoidCallback action) async {
    await _anim.reverse();
    if (mounted) _portal.hide();
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    action();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.collapsed && _portal.isShowing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_portal.isShowing) return;
        _anim.value = 0;
        _portal.hide();
      });
    }
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggle,
              ),
            ),
            CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              targetAnchor: Alignment.topLeft,
              followerAnchor: Alignment.bottomLeft,
              offset: const Offset(0, -4),
              child: UnconstrainedBox(
                child: FadeTransition(
                  opacity: _motion,
                  child: SlideTransition(
                    position: _slide,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _flyIcon(
                          tooltip: 'Galeri',
                          icon: Icons.photo_outlined,
                          onTap: () => _run(widget.onPickGallery),
                        ),
                        _flyIcon(
                          tooltip: 'Dosya',
                          icon: Icons.folder_outlined,
                          onTap: () => _run(widget.onPickFile),
                        ),
                        _flyIcon(
                          tooltip: 'Konum paylaş',
                          icon: Icons.location_on_outlined,
                          onTap: () => _run(widget.onShareLocation),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      child: widget.collapsed
          ? const SizedBox.shrink()
          : CompositedTransformTarget(
              link: _link,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  IconButton(
                    tooltip: 'Ekle',
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    constraints: _composerIconConstraints,
                    style: _composerIconStyle,
                    color: Colors.white70,
                    onPressed: widget.enabled ? _toggle : null,
                    icon: Transform.translate(
                      offset: const Offset(0, -1.5),
                      child: const Icon(Icons.attach_file, size: 24),
                    ),
                  ),
                  if (widget.showTyping)
                    const Positioned(
                      right: -4,
                      top: -5,
                      child: IgnorePointer(child: TypingBubble()),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _flyIcon({
    required String tooltip,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: const Color(0xFF1E1E1E),
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: tooltip,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          color: Colors.white70,
          onPressed: onTap,
          icon: Icon(icon, size: 24),
        ),
      ),
    );
  }
}


import 'dart:async';

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
import '../../services/moderation_service.dart';
import '../../services/nudge_service.dart';
import '../../services/settings_service.dart';
import '../../services/storage_service.dart';
import 'chat_search_screen.dart';
import 'group_details_screen.dart';
import 'media_capture_screen.dart';
import 'media_viewer_screen.dart';
import 'message_bubble.dart';

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
  bool _mediaUploading = false;
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
  String? _myUid;
  String? _highlightedMessageId;
  String? _pendingJumpId;
  bool _initialMessageHandled = false;
  final Map<String, GlobalKey> _messageKeys = {};
  final Map<String, Future<AppUser?>> _userFutures = {};
  bool _showJumpDown = false;
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _bumpIdle());
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _typingDebounce?.cancel();
    _readDebounce?.cancel();
    _messageController.removeListener(_onComposerChanged);
    _focusNode.removeListener(_onComposerFocus);
    _messageController.dispose();
    _scrollController.removeListener(_onScrollOffset);
    _scrollController.dispose();
    _focusNode.dispose();
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

  void _armIdleTimer({bool fast = false}) {
    _fastIdleTicks = fast;
    _idleTimer?.cancel();
    _idleTimer = Timer.periodic(Duration(milliseconds: fast ? 80 : 1000), (_) {
      if (!mounted) return;
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

  Future<void> _sendText() async {
    final text = _messageController.text;
    if (text.trim().isEmpty) return;

    final currentUser = context.read<AuthService>().currentUser!;
    try {
      await context.read<ModerationService>().ensureNotRestricted(
        currentUser.uid,
        currentUser.email ?? '',
      );
    } on AccountRestrictedException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
      return;
    }

    final editing = _editingMessage;
    if (editing != null) {
      await _saveEdit(editing, text);
      return;
    }

    _messageController.clear();
    final reply = _replyTo;
    final ttl = _expireSeconds;
    final pending = ChatMessage(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      senderId: _myUid!,
      text: text,
      createdAt: DateTime.now(),
      readBy: [_myUid!],
      replyToId: reply?.id,
      replyToText: reply?.text,
      replyToSenderId: reply?.senderId,
    );
    setState(() {
      _replyTo = null;
      _pendingOutgoing.add(pending);
    });
    _bumpIdle();

    try {
      final currentUserId = _myUid!;
      final chatService = _chatService!;
      if (widget.chatId.isEmpty && (widget.pendingEmail ?? '').isNotEmpty) {
        await chatService.sendPendingText(
          senderId: currentUserId,
          recipientEmail: widget.pendingEmail!,
          text: text,
          replyTo: reply,
          expireSeconds: ttl,
        );
      } else {
        await chatService.sendTextMessage(
          chatId: widget.chatId,
          senderId: currentUserId,
          text: text,
          replyTo: reply,
          expireSeconds: ttl,
        );
      }
      _typingSent = false;
      _scrollToBottom();
    } on ChatBlockedException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mesaj gönderilemedi. Tekrar deneyin.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _pendingOutgoing.removeWhere((item) => item.id == pending.id));
      }
    }
  }

  Future<void> _captureMedia() async {
    final captured = await Navigator.of(context).push<CapturedMedia>(
      MaterialPageRoute(builder: (_) => const MediaCaptureScreen()),
    );
    if (captured == null || !mounted) return;
    await _sendMedia(captured);
  }

  Future<void> _sendMedia(CapturedMedia captured) async {
    if (_mediaUploading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Önceki medya arka planda yükleniyor.')),
      );
    }
    setState(() => _mediaUploading = true);
    try {
      final uid = _myUid!;
      final folder = widget.chatId.isNotEmpty
          ? 'chat_media/${widget.chatId}'
          : 'pending_media/${ChatService.emailKey(widget.pendingEmail ?? uid)}';
      final url = await context.read<StorageService>().uploadChatMedia(
        folder: folder,
        file: captured.file,
        contentType: captured.contentType,
      );
      final type = captured.isVideo ? MessageType.video : MessageType.image;
      final chatService = _chatService!;
      if (widget.chatId.isEmpty && (widget.pendingEmail ?? '').isNotEmpty) {
        await chatService.sendPendingMedia(
          senderId: uid,
          recipientEmail: widget.pendingEmail!,
          mediaUrl: url,
          type: type,
          replyTo: _replyTo,
          expireSeconds: _expireSeconds,
        );
      } else {
        await chatService.sendMediaMessage(
          chatId: widget.chatId,
          senderId: uid,
          mediaUrl: url,
          type: type,
          replyTo: _replyTo,
          expireSeconds: _expireSeconds,
        );
      }
      if (mounted) setState(() => _replyTo = null);
      _scrollToBottom();
    } on MediaUploadException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (error, stackTrace) {
      debugPrint('HM_MEDIA_UPLOAD_FAILED: $error\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Medya gönderilemedi.')));
      }
    } finally {
      if (mounted) setState(() => _mediaUploading = false);
    }
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

  Future<void> _saveEdit(ChatMessage message, String text) async {
    if (widget.chatId.isEmpty || _isSending) return;
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mesaj düzenlenemedi. Tekrar deneyin.')),
        );
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

    var merged = _mergeMessages(messages);
    var guard = 0;
    while (!merged.any((message) => message.id == messageId) &&
        _hasMoreMessages &&
        guard < 24) {
      final loaded = await _loadOlderMessages();
      if (!loaded) break;
      merged = _mergeMessages(const []);
      guard += 1;
    }

    if (!merged.any((message) => message.id == messageId) &&
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
    if (!merged.any((message) => message.id == messageId)) {
      _pendingJumpId = null;
      return;
    }

    setState(() => _highlightedMessageId = messageId);
    await _ensureMessageVisible(messageId, merged);
    if (mounted) _pendingJumpId = null;
  }

  Future<void> _ensureMessageVisible(
    String messageId,
    List<ChatMessage> messages,
  ) async {
    final reversed = messages.reversed.toList();
    final index = reversed.indexWhere((message) => message.id == messageId);
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

  bool _pendingCoveredBy(ChatMessage pending, List<ChatMessage> server) {
    return server.any((message) {
      if (message.id.startsWith('local-')) return false;
      if (message.senderId != pending.senderId) return false;
      if (message.text != pending.text) return false;
      final a = message.createdAt;
      final b = pending.createdAt;
      if (a == null || b == null) return true;
      return a.difference(b).abs() <= const Duration(seconds: 20);
    });
  }

  bool _sameMessages(List<ChatMessage> a, List<ChatMessage> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].text != b[i].text ||
          a[i].readBy.length != b[i].readBy.length ||
          a[i].editedAt != b[i].editedAt) {
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
    if (settings.typingEnabled &&
        chat != null &&
        chat.isOtherTyping(widget.otherUserId)) {
      return 'Yazıyor...';
    }
    if (!settings.lastSeenEnabled) return '';
    if (user == null) return '';
    if (!user.shareLastSeen) return '';
    return ChatFormat.lastSeenLabel(user.lastSeen, isOnline: user.isOnline);
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bekleyen mesaj henüz silinemiyor.')),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mesaj silinemedi. Tekrar deneyin.')),
        );
      }
    }
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bu kayıt henüz aktif değil, kişi bildirilemez.'),
        ),
      );
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Bildirim gönderildi.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bildirim gönderilemedi. Tekrar deneyin.'),
        ),
      );
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kullanıcı gruptan çıkarıldı.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _onMessageLongPress(
    ChatMessage message,
    bool isMine,
    ChatRoom? chat,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF161616),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!message.hasMedia)
                ListTile(
                  leading: const Icon(Icons.copy, color: Colors.white70),
                  title: const Text(
                    'Kopyala',
                    style: TextStyle(color: Colors.white70),
                  ),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: message.text));
                    Navigator.pop(context);
                  },
                ),
              if (message.hasMedia)
                ListTile(
                  leading: const Icon(
                    Icons.download_outlined,
                    color: Colors.white70,
                  ),
                  title: const Text(
                    'Indir',
                    style: TextStyle(color: Colors.white70),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _downloadMedia(message);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.reply, color: Colors.white70),
                title: const Text(
                  'Yanitla',
                  style: TextStyle(color: Colors.white70),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _startReply(message);
                },
              ),
              if (widget.chatId.isNotEmpty)
                ListTile(
                  leading: const Icon(
                    Icons.info_outline,
                    color: Colors.white70,
                  ),
                  title: const Text(
                    'Mesaj ayrıntıları',
                    style: TextStyle(color: Colors.white70),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showMessageDetails(message);
                  },
                ),
              if (isMine &&
                  widget.chatId.isNotEmpty &&
                  !message.hasMedia &&
                  !message.deletedForEveryone &&
                  !message.isExpired())
                ListTile(
                  leading: const Icon(
                    Icons.edit_outlined,
                    color: Colors.white70,
                  ),
                  title: const Text(
                    'Düzenle',
                    style: TextStyle(color: Colors.white70),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _startEdit(message);
                  },
                ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  color: Colors.white70,
                ),
                title: const Text(
                  'Benden sil',
                  style: TextStyle(color: Colors.white70),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  await _deleteMessage(message, forEveryone: false);
                },
              ),
              if (!isMine && widget.chatId.isNotEmpty)
                ListTile(
                  leading: const Icon(
                    Icons.flag_outlined,
                    color: Color(0xFFFFCC80),
                  ),
                  title: const Text(
                    'Mesajı bildir',
                    style: TextStyle(color: Color(0xFFFFCC80)),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _reportMessage(message);
                  },
                ),
              if (!isMine &&
                  chat?.isGroup == true &&
                  chat!.isAdmin(_myUid ?? '') &&
                  !chat.isAdmin(message.senderId))
                ListTile(
                  leading: const Icon(
                    Icons.person_remove_outlined,
                    color: Color(0xFFFF8A80),
                  ),
                  title: const Text(
                    'Göndereni gruptan çıkar',
                    style: TextStyle(color: Color(0xFFFF8A80)),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _removeMessageSender(chat, message);
                  },
                ),
              if (isMine)
                ListTile(
                  leading: const Icon(
                    Icons.delete_forever_outlined,
                    color: Color(0xFFFF8A80),
                  ),
                  title: const Text(
                    'Herkesten sil',
                    style: TextStyle(color: Color(0xFFFF8A80)),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    await _deleteMessage(message, forEveryone: true);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  void _openMedia(ChatMessage message) {
    final url = message.mediaUrl;
    if (url == null || url.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MediaViewerScreen(
          url: url,
          isVideo: message.type == MessageType.video,
        ),
      ),
    );
  }

  Future<void> _downloadMedia(ChatMessage message) async {
    final url = message.mediaUrl;
    if (url == null || url.isEmpty) return;
    try {
      await context.read<StorageService>().downloadToGallery(
        mediaUrl: url,
        isVideo: message.type == MessageType.video,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Galeriye indirildi.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Medya indirilemedi.')));
    }
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
            return Scaffold(
              backgroundColor: IdleWarningLook.scaffold(warning),
              floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
              floatingActionButton: _showJumpDown
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 72),
                      child: FloatingActionButton.small(
                        backgroundColor: const Color(0xFF2A2A2A),
                        foregroundColor: Colors.white70,
                        onPressed: _scrollToBottom,
                        child: const Icon(Icons.arrow_downward),
                      ),
                    )
                  : null,
              appBar: AppBar(
                backgroundColor: IdleWarningLook.appBar(warning),
                foregroundColor: Colors.white70,
                elevation: 0,
                title: StreamBuilder<AppUser?>(
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
                          TickingBuilder(
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
                        ],
                      ),
                    );
                  },
                ),
                actions: [
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
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) => _onMenuSelected(value, pref, chat),
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'search',
                        child: Text(
                          'Bu sohbette ara',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'first',
                        child: Text(
                          'İlk mesaja git',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                      if (!isGroup)
                        const PopupMenuItem(
                          value: 'person',
                          child: Text(
                            'Kişi ayrıntısı',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                      if (isGroup)
                        const PopupMenuItem(
                          value: 'group',
                          child: Text(
                            'Grup ayrıntıları',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                      const PopupMenuItem(
                        value: 'clear',
                        child: Text(
                          'Sohbeti temizle',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                      if (!isGroup)
                        PopupMenuItem(
                          value: 'block',
                          child: Text(
                            chat?.blockedBy.contains(currentUserId) == true
                                ? 'Engeli kaldır'
                                : 'Kişiyi engelle',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                      if (!isGroup)
                        const PopupMenuItem(
                          value: 'report_user',
                          child: Text(
                            'Kişiyi bildir',
                            style: TextStyle(color: Color(0xFFFFCC80)),
                          ),
                        ),
                      const PopupMenuItem(
                        value: 'calculator',
                        child: Text(
                          'Hesap makinesine dön',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
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
                  Expanded(
                    child: StreamBuilder<List<ChatMessage>>(
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
                        final pending = _pendingOutgoing
                            .where(
                              (item) => !_pendingCoveredBy(item, visible),
                            )
                            .toList();
                        if (pending.length != _pendingOutgoing.length) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            setState(() {
                              _pendingOutgoing.removeWhere(
                                (item) => _pendingCoveredBy(item, visible),
                              );
                            });
                          });
                        }
                        final messages = [...visible, ...pending];

                        if (!_initialMessageHandled &&
                            (widget.initialMessageId ?? '').isNotEmpty &&
                            messages.isNotEmpty) {
                          _initialMessageHandled = true;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            _jumpToMessage(widget.initialMessageId!, messages);
                          });
                        }

                        if (messages.length != _lastMarkedMessages.length ||
                            !_sameMessages(messages, _lastMarkedMessages)) {
                          _lastMarkedMessages = List<ChatMessage>.from(
                            messages,
                          );
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _scheduleMarkAsRead(messages);
                          });
                          if (!_showJumpDown && _pendingJumpId == null) {
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

                            final messageKey = _messageKeys.putIfAbsent(
                              message.id,
                              () => GlobalKey(),
                            );
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
                                FutureBuilder<AppUser?>(
                                  future: isGroup && !isMine
                                      ? _userFor(message.senderId)
                                      : null,
                                  builder: (context, senderSnapshot) {
                                    final pending = message.id.startsWith(
                                      'local-',
                                    );
                                    return Dismissible(
                                      key: ValueKey('swipe-${message.id}'),
                                      direction: DismissDirection.startToEnd,
                                      confirmDismiss: (_) async {
                                        _startReply(message);
                                        return false;
                                      },
                                      background: const Align(
                                        alignment: Alignment.centerLeft,
                                        child: Padding(
                                          padding: EdgeInsets.only(left: 20),
                                          child: Icon(
                                            Icons.reply,
                                            color: Colors.white38,
                                          ),
                                        ),
                                      ),
                                      child: RepaintBoundary(
                                        child: MessageBubble(
                                          message: message,
                                          isMine: isMine,
                                          isRead: isRead,
                                          pending: pending,
                                          senderLabel: isGroup && !isMine
                                              ? (senderSnapshot
                                                        .data
                                                        ?.visibleName ??
                                                    'Grup üyesi')
                                              : null,
                                          highlighted:
                                              message.id ==
                                              _highlightedMessageId,
                                          onMediaTap: () => _openMedia(message),
                                          onReplyTap:
                                              (message.replyToId ?? '').isEmpty
                                              ? null
                                              : () => _jumpToMessage(
                                                  message.replyToId!,
                                                  messages,
                                                ),
                                          onLongPress: () =>
                                              _onMessageLongPress(
                                                message,
                                                isMine,
                                                chat,
                                              ),
                                        ),
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
                  ),
                  TickingBuilder(
                    interval: const Duration(seconds: 2),
                    builder: (_) {
                      final typing =
                          !isGroup &&
                          settings.typingEnabled &&
                          chat != null &&
                          chat.isOtherTyping(widget.otherUserId);
                      if (!typing) return const SizedBox.shrink();
                      return Container(
                        width: double.infinity,
                        color: const Color(0xFF12181E),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: const Text(
                          'Yazıyor...',
                          style: TextStyle(
                            color: Color(0xFF90CAF9),
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      );
                    },
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
                      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
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
                              _replyTo!.text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          IconButton(
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
                      padding: const EdgeInsets.fromLTRB(8, 6, 4, 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          IconButton(
                            tooltip: _ttlLabel(),
                            color: _expireSeconds == null
                                ? Colors.white38
                                : const Color(0xFFFFCC80),
                            onPressed: blocked ? null : _cycleTtl,
                            icon: Icon(
                              _expireSeconds == null
                                  ? Icons.timer_off_outlined
                                  : Icons.timer_outlined,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Fotoğraf / video',
                            color: Colors.white70,
                            onPressed: blocked ? null : _captureMedia,
                            icon: const Icon(Icons.photo_camera_outlined),
                          ),
                          Expanded(
                            child: Focus(
                              onKeyEvent: _onKey,
                              child: TextField(
                                controller: _messageController,
                                focusNode: _focusNode,
                                enabled: !blocked,
                                minLines: 1,
                                maxLines: 5,
                                textCapitalization: TextCapitalization.sentences,
                                style: const TextStyle(color: Colors.white),
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
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
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
                                textInputAction: TextInputAction.send,
                                onSubmitted: blocked
                                    ? null
                                    : (_) => _sendText(),
                              ),
                            ),
                          ),
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              IconButton(
                                color: Colors.white70,
                                onPressed: blocked ? null : _sendText,
                                icon: const Icon(Icons.arrow_upward),
                              ),
                              if (_mediaUploading)
                                const Positioned(
                                  top: 6,
                                  right: 6,
                                  child: IgnorePointer(
                                    child: SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.8,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/chat_format.dart';
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
import '../../services/settings_service.dart';
import 'media_gallery_screen.dart';
import 'message_bubble.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.chatId,
    required this.otherUserId,
    required this.otherUserName,
    this.pendingEmail,
    this.onExitToCalculator,
  });

  final String chatId;
  final String otherUserId;
  final String otherUserName;
  final String? pendingEmail;
  final VoidCallback? onExitToCalculator;

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
  bool _isSending = false;
  bool _typingSent = false;
  int? _expireSeconds;
  ChatMessage? _replyTo;
  ChatMessage? _editingMessage;
  List<ChatMessage> _lastMarkedMessages = [];
  List<String> _lastPurgedIds = [];
  Stream<Map<String, ChatPref>>? _prefsStream;
  Stream<ChatRoom?>? _chatStream;
  Stream<List<ChatMessage>>? _messagesStream;
  Stream<AppUser?>? _otherUserStream;

  static const _ttlOptions = <int?>[null, 10, 60];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final authService = context.read<AuthService>();
    final chatService = context.read<ChatService>();
    final uid = authService.currentUser!.uid;
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
  }

  @override
  void dispose() {
    _typingDebounce?.cancel();
    _messageController.removeListener(_onComposerChanged);
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _setTyping(false);
    super.dispose();
  }

  void _onComposerChanged() {
    final hasText = _messageController.text.trim().isNotEmpty;
    if (hasText && !_typingSent) {
      _typingSent = true;
      _setTyping(true);
    }
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(seconds: 2), () {
      if (!hasText && _typingSent) {
        _typingSent = false;
        _setTyping(false);
      } else if (hasText) {
        _setTyping(true);
      }
    });
    if (!hasText && _typingSent) {
      _typingSent = false;
      _setTyping(false);
    }
  }

  Future<void> _setTyping(bool typing) async {
    if (!mounted || widget.chatId.isEmpty) return;
    final uid = context.read<AuthService>().currentUser?.uid;
    if (uid == null) return;
    final allowed = context.read<SettingsService>().typingEnabled;
    try {
      await context.read<ChatService>().setTyping(
            chatId: widget.chatId,
            userId: uid,
            typing: typing && allowed,
          );
    } catch (_) {}
  }

  Future<void> _sendText() async {
    final text = _messageController.text;
    if (text.trim().isEmpty || _isSending) return;

    final currentUser = context.read<AuthService>().currentUser!;
    try {
      await context.read<ModerationService>().ensureNotRestricted(
            currentUser.uid,
            currentUser.email ?? '',
          );
    } on AccountRestrictedException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
      return;
    }

    final editing = _editingMessage;
    if (editing != null) {
      await _saveEdit(editing, text);
      return;
    }

    setState(() => _isSending = true);
    _messageController.clear();
    final reply = _replyTo;
    final ttl = _expireSeconds;
    setState(() => _replyTo = null);

    try {
      final currentUserId = context.read<AuthService>().currentUser!.uid;
      final chatService = context.read<ChatService>();
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mesaj gonderilemedi. Tekrar deneyin.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
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
          const SnackBar(content: Text('Mesaj duzenlenemedi. Tekrar deneyin.')),
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

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _markAsRead(List<ChatMessage> messages) async {
    if (widget.chatId.isEmpty) return;
    final currentUserId = context.read<AuthService>().currentUser!.uid;
    final receipts = context.read<SettingsService>().readReceiptsEnabled;
    await context.read<ChatService>().markMessagesAsRead(
          chatId: widget.chatId,
          readerId: currentUserId,
          messages: messages,
          writeReceipts: receipts,
        );
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

  String _presenceText(AppUser? user, ChatRoom? chat, SettingsService settings) {
    if (widget.chatId.isEmpty) {
      return 'Cevrimdisi iletilecek';
    }
    if (settings.typingEnabled &&
        chat != null &&
        chat.isOtherTyping(widget.otherUserId)) {
      return 'Yaziyor...';
    }
    if (!settings.lastSeenEnabled) return '';
    if (user == null) return '';
    if (!user.shareLastSeen) return '';
    return ChatFormat.lastSeenLabel(user.lastSeen, isOnline: user.isOnline);
  }

  void _cycleTtl() {
    final index = _ttlOptions.indexOf(_expireSeconds);
    setState(() => _expireSeconds = _ttlOptions[(index + 1) % _ttlOptions.length]);
  }

  String _ttlLabel() {
    if (_expireSeconds == 10) return '10 sn';
    if (_expireSeconds == 60) return '1 dk';
    return 'Sure yok';
  }

  void _exitToCalculator() {
    final exit = widget.onExitToCalculator;
    if (exit != null) {
      exit();
      return;
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _onMenuSelected(String value, ChatPref? pref, ChatRoom? chat) async {
    final auth = context.read<AuthService>();
    final chatService = context.read<ChatService>();
    final uid = auth.currentUser!.uid;

    switch (value) {
      case 'clear':
        final ok = await _confirm('Bu kayittaki mesajlar sizde temizlensin mi?');
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
          final ok = await _confirm('Bu kisi engellensin mi?');
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
      case 'media':
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MediaGalleryScreen(
              chatId: widget.chatId,
              viewerId: uid,
              clearedAt: pref?.clearedAt,
            ),
          ),
        );
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
            child: const Text('Vazgec'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteMessage(ChatMessage message, {required bool forEveryone}) async {
    if (widget.chatId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bekleyen mesaj henuz silinemiyor.')),
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
                  title: Text(item.label, style: const TextStyle(color: Colors.white70)),
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
          content: Text('Bu kayit henuz aktif degil, kisi bildirilemez.'),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bildirim gonderildi.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bildirim gonderilemedi. Tekrar deneyin.')),
      );
    }
  }

  Future<void> _onMessageLongPress(ChatMessage message, bool isMine) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF161616),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.copy, color: Colors.white70),
                title: const Text('Kopyala', style: TextStyle(color: Colors.white70)),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: message.text));
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.reply, color: Colors.white70),
                title: const Text('Yanitla', style: TextStyle(color: Colors.white70)),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _replyTo = message;
                    _editingMessage = null;
                  });
                  _focusNode.requestFocus();
                },
              ),
              if (isMine &&
                  widget.chatId.isNotEmpty &&
                  message.type == MessageType.text &&
                  !message.deletedForEveryone &&
                  !message.isExpired())
                ListTile(
                  leading: const Icon(Icons.edit_outlined, color: Colors.white70),
                  title: const Text('Duzenle', style: TextStyle(color: Colors.white70)),
                  onTap: () {
                    Navigator.pop(context);
                    _startEdit(message);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.white70),
                title: const Text('Benden sil', style: TextStyle(color: Colors.white70)),
                onTap: () async {
                  Navigator.pop(context);
                  await _deleteMessage(message, forEveryone: false);
                },
              ),
              if (!isMine && widget.chatId.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.flag_outlined, color: Color(0xFFFFCC80)),
                  title: const Text(
                    'Mesaji bildir',
                    style: TextStyle(color: Color(0xFFFFCC80)),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _reportMessage(message);
                  },
                ),
              if (isMine)
                ListTile(
                  leading: const Icon(Icons.delete_forever_outlined, color: Color(0xFFFF8A80)),
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

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.enter &&
        event.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    final shift = HardwareKeyboard.instance.logicalKeysPressed.contains(
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
            final blocked = chat?.isBlocked() == true;

            return Scaffold(
              backgroundColor: const Color(0xFF0B0B0B),
              appBar: AppBar(
                backgroundColor: const Color(0xFF0B0B0B),
                foregroundColor: Colors.white70,
                elevation: 0,
                title: StreamBuilder<AppUser?>(
                  stream: _otherUserStream,
                  builder: (context, snapshot) {
                    final user = snapshot.data;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.email ?? widget.otherUserName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        TickingBuilder(
                          interval: const Duration(seconds: 2),
                          builder: (_) {
                            final text = _presenceText(user, chat, settings);
                            final typing = text == 'Yaziyor...';
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
                    );
                  },
                ),
                actions: [
                  IconButton(
                    tooltip: 'Hesap makinesine don',
                    icon: const Icon(Icons.calculate_outlined),
                    onPressed: _exitToCalculator,
                  ),
                  PopupMenuButton<String>(
                    color: const Color(0xFF161616),
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) => _onMenuSelected(value, pref, chat),
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'clear',
                        child: Text('Sohbeti temizle', style: TextStyle(color: Colors.white70)),
                      ),
                      PopupMenuItem(
                        value: 'block',
                        child: Text(
                          chat?.blockedBy.contains(currentUserId) == true
                              ? 'Engeli kaldir'
                              : 'Kisisi engelle',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'report_user',
                        child: Text(
                          'Kisiyi bildir',
                          style: TextStyle(color: Color(0xFFFFCC80)),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'media',
                        child: Text('Medyayi gor', style: TextStyle(color: Colors.white70)),
                      ),
                      const PopupMenuItem(
                        value: 'calculator',
                        child: Text(
                          'Hesap makinesine don',
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
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: const Text(
                        'Bu yazisma engellenmis. Yeni mesaj gonderilemez.',
                        style: TextStyle(color: Color(0xFFFF8A80), fontSize: 12),
                      ),
                    ),
                  Expanded(
                    child: StreamBuilder<List<ChatMessage>>(
                      stream: _messagesStream,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting &&
                            !snapshot.hasData &&
                            _lastMarkedMessages.isEmpty) {
                          return const Center(
                            child: CircularProgressIndicator(color: Colors.white24),
                          );
                        }

                        if (snapshot.hasError &&
                            !snapshot.hasData &&
                            _lastMarkedMessages.isEmpty) {
                          return const Center(
                            child: Text(
                              'Mesajlar yuklenemedi.',
                              style: TextStyle(color: Colors.white38),
                            ),
                          );
                        }

                        final raw = snapshot.data ?? _lastMarkedMessages;
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

                        final messages = raw
                            .where(
                              (m) => m.isVisibleTo(
                                currentUserId,
                                clearedAt: pref?.clearedAt,
                              ),
                            )
                            .toList();

                        if (messages.length != _lastMarkedMessages.length ||
                            !_sameMessages(messages, _lastMarkedMessages)) {
                          _lastMarkedMessages = List<ChatMessage>.from(messages);
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _markAsRead(messages);
                          });
                          _scrollToBottom();
                        }

                        if (messages.isEmpty) {
                          return const Center(
                            child: Text(
                              'Ilk mesaji yazin.',
                              style: TextStyle(color: Colors.white38),
                            ),
                          );
                        }

                        return ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final message = messages[index];
                            final showDay = index == 0 ||
                                !ChatFormat.isSameDay(
                                  messages[index - 1].createdAt,
                                  message.createdAt,
                                );
                            final isMine = message.senderId == currentUserId;
                            final isRead = settings.readReceiptsEnabled &&
                                message.readBy.any((id) => id != currentUserId);

                            return Column(
                              children: [
                                if (showDay && message.createdAt != null)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    child: Text(
                                      ChatFormat.dayLabel(message.createdAt!),
                                      style: const TextStyle(
                                        color: Colors.white30,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                MessageBubble(
                                  message: message,
                                  isMine: isMine,
                                  isRead: isRead,
                                  onLongPress: () =>
                                      _onMessageLongPress(message, isMine),
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
                      final typing = settings.typingEnabled &&
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
                          'Yaziyor...',
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
                          const Icon(Icons.edit_outlined, color: Colors.white38, size: 18),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Mesaji duzenle',
                              style: TextStyle(color: Colors.white54, fontSize: 13),
                            ),
                          ),
                          IconButton(
                            onPressed: _cancelEdit,
                            icon: const Icon(Icons.close, color: Colors.white38, size: 18),
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
                          const Icon(Icons.reply, color: Colors.white38, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _replyTo!.text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white54, fontSize: 13),
                            ),
                          ),
                          IconButton(
                            onPressed: () => setState(() => _replyTo = null),
                            icon: const Icon(Icons.close, color: Colors.white38, size: 18),
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
                          Expanded(
                            child: Focus(
                              onKeyEvent: _onKey,
                              child: TextField(
                                controller: _messageController,
                                focusNode: _focusNode,
                                enabled: !blocked,
                                minLines: 1,
                                maxLines: 5,
                                style: const TextStyle(color: Colors.white),
                                cursorColor: Colors.white54,
                                decoration: InputDecoration(
                                  hintText: blocked
                                      ? 'Engellendi'
                                      : (_editingMessage != null
                                          ? 'Mesaji duzenle...'
                                          : 'Yazi...'),
                                  hintStyle: const TextStyle(color: Colors.white30),
                                  filled: true,
                                  fillColor: const Color(0xFF1A1A1A),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                  isDense: true,
                                  suffixText: _expireSeconds == null ? null : _ttlLabel(),
                                  suffixStyle: const TextStyle(
                                    color: Color(0xFFFFCC80),
                                    fontSize: 11,
                                  ),
                                ),
                                textInputAction: TextInputAction.send,
                                onSubmitted: blocked ? null : (_) => _sendText(),
                              ),
                            ),
                          ),
                          IconButton(
                            color: Colors.white70,
                            onPressed: (_isSending || blocked) ? null : _sendText,
                            icon: _isSending
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white54,
                                    ),
                                  )
                                : const Icon(Icons.arrow_upward),
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

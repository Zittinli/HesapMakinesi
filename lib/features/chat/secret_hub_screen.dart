import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/admin_config.dart';
import '../../core/chat_format.dart';
import '../../core/ticking_builder.dart';
import '../../models/chat_model.dart';
import '../../models/chat_pref_model.dart';
import '../../models/pending_thread_model.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/chat_service.dart';
import '../../services/settings_service.dart';
import '../chat/chat_screen.dart';
import '../settings/admin_home_screen.dart';
import '../settings/settings_screen.dart';

class SecretHubScreen extends StatefulWidget {
  const SecretHubScreen({
    super.key,
    required this.onExitToCalculator,
  });

  final VoidCallback onExitToCalculator;

  @override
  State<SecretHubScreen> createState() => _SecretHubScreenState();
}

class _SecretHubScreenState extends State<SecretHubScreen> {
  final _emailController = TextEditingController();
  final _searchController = TextEditingController();
  bool _isStarting = false;
  String? _error;
  Stream<List<ChatRoom>>? _chatsStream;
  Stream<Map<String, ChatPref>>? _prefsStream;
  Stream<List<PendingThread>>? _pendingStream;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final authService = context.read<AuthService>();
    final chatService = context.read<ChatService>();
    final uid = authService.currentUser!.uid;
    _chatsStream ??= chatService.watchUserChats(uid);
    _prefsStream ??= chatService.watchChatPrefs(uid);
    _pendingStream ??= chatService.watchPendingSent(uid);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openChatWithEmail() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Alici e-posta girin.');
      return;
    }

    setState(() {
      _isStarting = true;
      _error = null;
    });

    try {
      final authService = context.read<AuthService>();
      final chatService = context.read<ChatService>();
      final currentUserId = authService.currentUser!.uid;

      final user = await authService.findUserByEmail(email);
      if (user?.id == currentUserId) {
        setState(() => _error = 'Kendi adresinize mesaj atamazsiniz.');
        return;
      }

      if (user == null) {
        await chatService.openPendingThread(
          senderId: currentUserId,
          recipientEmail: email,
        );
        if (!mounted) return;
        _emailController.clear();
        await _openChat(
          chatId: '',
          otherUserId: '',
          otherUserName: email.trim().toLowerCase(),
          pendingEmail: email.trim().toLowerCase(),
        );
        return;
      }

      final String chatId;
      try {
        chatId = await chatService.getOrCreateChat(currentUserId, user.id);
        try {
          await chatService.promotePendingToChat(
            senderId: currentUserId,
            recipientEmail: user.email,
            chatId: chatId,
          );
        } catch (_) {}
      } on ChatBlockedException catch (error) {
        setState(() => _error = error.message);
        return;
      }

      if (!mounted) return;
      _emailController.clear();
      await _openChat(
        chatId: chatId,
        otherUserId: user.id,
        otherUserName:
            user.displayName.isNotEmpty ? user.displayName : user.email,
        pendingEmail: user.email,
      );
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Sohbet acilamadi. Tekrar deneyin.');
      }
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  Future<void> _openChat({
    required String chatId,
    required String otherUserId,
    required String otherUserName,
    String? pendingEmail,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          chatId: chatId,
          otherUserId: otherUserId,
          otherUserName: otherUserName,
          pendingEmail: pendingEmail,
          onExitToCalculator: widget.onExitToCalculator,
        ),
      ),
    );
  }

  List<ChatRoom> _hiddenChats(
    List<ChatRoom> chats,
    Map<String, ChatPref> prefs,
  ) {
    return chats.where((chat) => prefs[chat.id]?.hidden == true).toList();
  }

  Future<void> _restoreAndOpenChat(ChatRoom chat) async {
    final authService = context.read<AuthService>();
    final chatService = context.read<ChatService>();
    final uid = authService.currentUser!.uid;
    final otherId = chat.otherParticipantId(uid);
    await chatService.setHidden(userId: uid, chatId: chat.id, hidden: false);
    if (!mounted) return;
    final other = otherId.isEmpty ? null : await authService.watchUser(otherId).first;
    if (!mounted) return;
    await _openChat(
      chatId: chat.id,
      otherUserId: otherId,
      otherUserName: other?.email.isNotEmpty == true
          ? other!.email
          : (other?.displayName.isNotEmpty == true ? other!.displayName : 'Kayit'),
      pendingEmail: other?.email,
    );
  }

  Future<void> _showHiddenChats(List<ChatRoom> hidden) async {
    if (hidden.isEmpty) return;
    final authService = context.read<AuthService>();
    final uid = authService.currentUser!.uid;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF161616),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  'Gizlenen kayitlar',
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Dokununca tekrar listede gorunur.',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ),
              ...hidden.map((chat) {
                final otherId = chat.otherParticipantId(uid);
                return ListTile(
                  leading: const Icon(
                    Icons.visibility_off_outlined,
                    color: Colors.white54,
                  ),
                  title: StreamBuilder<AppUser?>(
                    stream: otherId.isEmpty
                        ? Stream.value(null)
                        : authService.watchUser(otherId),
                    builder: (context, snapshot) {
                      final user = snapshot.data;
                      final label = user?.email.isNotEmpty == true
                          ? user!.email
                          : (user?.displayName.isNotEmpty == true
                              ? user!.displayName
                              : 'Gizli kayit');
                      return Text(
                        label,
                        style: const TextStyle(color: Colors.white70),
                      );
                    },
                  ),
                  subtitle: Text(
                    chat.lastMessage.isEmpty ? 'Kayit gizlendi' : chat.lastMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white38),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _restoreAndOpenChat(chat);
                  },
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  List<ChatRoom> _visibleChats(
    List<ChatRoom> chats,
    Map<String, ChatPref> prefs,
    String currentUserId,
    Map<String, AppUser?> users,
  ) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = chats.where((chat) {
      final pref = prefs[chat.id] ?? ChatPref.empty(chat.id);
      if (pref.hidden) return false;
      if (query.isEmpty) return true;
      final other = users[chat.otherParticipantId(currentUserId)];
      final haystack = [
        chat.lastMessage,
        other?.email ?? '',
        other?.displayName ?? '',
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();

    filtered.sort((a, b) {
      final pa = prefs[a.id];
      final pb = prefs[b.id];
      final aPinned = pa?.pinned == true;
      final bPinned = pb?.pinned == true;
      if (aPinned != bPinned) return aPinned ? -1 : 1;
      if (aPinned && bPinned) {
        return (pb?.pinnedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(pa?.pinnedAt ?? DateTime.fromMillisecondsSinceEpoch(0));
      }
      return (b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0));
    });
    return filtered;
  }

  Future<void> _showChatMenu({
    required ChatRoom chat,
    required ChatPref pref,
    required String currentUserId,
  }) async {
    final chatService = context.read<ChatService>();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF161616),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  pref.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                  color: Colors.white70,
                ),
                title: Text(
                  pref.pinned ? 'Sabiti kaldir' : 'Sabitle',
                  style: const TextStyle(color: Colors.white70),
                ),
                onTap: () {
                  Navigator.pop(context);
                  chatService.setPinned(
                    userId: currentUserId,
                    chatId: chat.id,
                    pinned: !pref.pinned,
                  );
                },
              ),
              ListTile(
                leading: Icon(
                  pref.muted ? Icons.volume_up_outlined : Icons.volume_off_outlined,
                  color: Colors.white70,
                ),
                title: Text(
                  pref.muted ? 'Sesi ac' : 'Sessize al',
                  style: const TextStyle(color: Colors.white70),
                ),
                onTap: () {
                  Navigator.pop(context);
                  chatService.setMuted(
                    userId: currentUserId,
                    chatId: chat.id,
                    muted: !pref.muted,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.visibility_off_outlined, color: Colors.white70),
                title: const Text('Gizle', style: TextStyle(color: Colors.white70)),
                onTap: () {
                  Navigator.pop(context);
                  chatService.setHidden(
                    userId: currentUserId,
                    chatId: chat.id,
                    hidden: true,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Color(0xFFFF8A80)),
                title: const Text('Sil', style: TextStyle(color: Color(0xFFFF8A80))),
                onTap: () async {
                  Navigator.pop(context);
                  final ok = await _confirm('Bu kayit listeden silinsin mi?');
                  if (ok == true) {
                    await chatService.deleteChatForMe(
                      userId: currentUserId,
                      chatId: chat.id,
                    );
                  }
                },
              ),
            ],
          ),
        );
      },
    );
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

  @override
  Widget build(BuildContext context) {
    final authService = context.read<AuthService>();
    final chatService = context.read<ChatService>();
    final currentUserId = authService.currentUser!.uid;
    final myEmail = authService.currentUser?.email ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B0B),
        foregroundColor: Colors.white70,
        elevation: 0,
        title: const Text(
          'Kayitlar',
          style: TextStyle(fontWeight: FontWeight.w400, letterSpacing: 0.5),
        ),
        leading: IconButton(
          tooltip: 'Hesap makinesine don',
          icon: const Icon(Icons.close),
          onPressed: widget.onExitToCalculator,
        ),
        actions: [
          if (AdminConfig.isAdminEmail(myEmail))
            IconButton(
              tooltip: 'Yonetim',
              icon: const Icon(Icons.shield_outlined, size: 22),
              color: const Color(0xFFFFCC80),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AdminHomeScreen(
                      onExitToCalculator: widget.onExitToCalculator,
                    ),
                  ),
                );
              },
            ),
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
            icon: const Icon(Icons.settings_outlined, size: 18, color: Colors.white70),
            label: const Text(
              'Ayarlar',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          IconButton(
            tooltip: 'Hesap makinesine don',
            icon: const Icon(Icons.calculate_outlined, size: 22),
            onPressed: widget.onExitToCalculator,
          ),
          IconButton(
            tooltip: 'Cikis',
            icon: const Icon(Icons.logout, size: 20),
            onPressed: () => authService.signOut(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  myEmail,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Mesaj gonderilecek e-posta',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Karsi tarafin su an acik olmasi gerekmez.',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: Colors.white),
                  cursorColor: Colors.white54,
                  decoration: _fieldDecoration('ornek@mail.com'),
                  onSubmitted: (_) => _openChatWithEmail(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 13),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2A2A2A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _isStarting ? null : _openChatWithEmail,
                  child: _isStarting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white54,
                          ),
                        )
                      : const Text('Devam'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SettingsScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.settings_outlined, size: 18),
                  label: const Text('Ayarlar'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(color: Colors.white),
                  cursorColor: Colors.white54,
                  decoration: _fieldDecoration('Kayitlarda ara').copyWith(
                    prefixIcon: const Icon(Icons.search, color: Colors.white30, size: 20),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFF222222)),
          Expanded(
            child: StreamBuilder<List<PendingThread>>(
              stream: _pendingStream,
              builder: (context, pendingSnapshot) {
                return StreamBuilder<List<ChatRoom>>(
                  stream: _chatsStream,
                  builder: (context, chatSnapshot) {
                    return StreamBuilder<Map<String, ChatPref>>(
                      stream: _prefsStream,
                      builder: (context, prefSnapshot) {
                        if (chatSnapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(color: Colors.white24),
                          );
                        }

                        final chats = chatSnapshot.data ?? [];
                        final prefs = prefSnapshot.data ?? {};
                        final pending = pendingSnapshot.data ?? [];
                        final hidden = _hiddenChats(chats, prefs);
                        final query = _searchController.text.trim().toLowerCase();
                        final visiblePending = pending.where((item) {
                          if (query.isEmpty) return true;
                          return item.recipientEmail.contains(query) ||
                              item.lastMessage.toLowerCase().contains(query);
                        }).toList();

                        if (chats.isEmpty && visiblePending.isEmpty) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'Henuz kayit yok.\nUstte e-posta girerek baslatin.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white38, height: 1.4),
                              ),
                            ),
                          );
                        }

                        return Column(
                          children: [
                            ListTile(
                              dense: true,
                              leading: const Icon(
                                Icons.settings_outlined,
                                color: Colors.white38,
                                size: 20,
                              ),
                              title: const Text(
                                'Ayarlar',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 14,
                                ),
                              ),
                              trailing: const Icon(
                                Icons.chevron_right,
                                color: Colors.white30,
                              ),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const SettingsScreen(),
                                  ),
                                );
                              },
                            ),
                            if (hidden.isNotEmpty)
                              ListTile(
                                dense: true,
                                leading: const Icon(
                                  Icons.visibility_off_outlined,
                                  color: Colors.white38,
                                  size: 20,
                                ),
                                title: Text(
                                  'Gizlenenler (${hidden.length})',
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 14,
                                  ),
                                ),
                                trailing: const Icon(
                                  Icons.chevron_right,
                                  color: Colors.white30,
                                ),
                                onTap: () => _showHiddenChats(hidden),
                              ),
                            ...visiblePending.map((item) {
                              return ListTile(
                                textColor: Colors.white70,
                                leading: CircleAvatar(
                                  radius: 20,
                                  backgroundColor: const Color(0xFF2A2A2A),
                                  child: Text(
                                    ChatFormat.initials(item.recipientEmail),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                title: Text(item.recipientEmail),
                                subtitle: Text(
                                  item.lastMessage.isEmpty
                                      ? 'Cevrimdisi iletilecek'
                                      : item.lastMessage,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white38),
                                ),
                                trailing: const Text(
                                  'Bekliyor',
                                  style: TextStyle(
                                    color: Colors.white30,
                                    fontSize: 12,
                                  ),
                                ),
                                onTap: () => _openChat(
                                  chatId: '',
                                  otherUserId: '',
                                  otherUserName: item.recipientEmail,
                                  pendingEmail: item.recipientEmail,
                                ),
                              );
                            }),
                            if (chats.isNotEmpty)
                              Expanded(
                                child: _ChatRecordsList(
                                  chats: chats,
                                  prefs: prefs,
                                  currentUserId: currentUserId,
                                  searchQuery: _searchController.text,
                                  filter: _visibleChats,
                                  onOpen: (chat, title) => _openChat(
                                    chatId: chat.id,
                                    otherUserId:
                                        chat.otherParticipantId(currentUserId),
                                    otherUserName: title,
                                    pendingEmail:
                                        title.contains('@') ? title : null,
                                  ),
                                  onMenu: (chat, pref) => _showChatMenu(
                                    chat: chat,
                                    pref: pref,
                                    currentUserId: currentUserId,
                                  ),
                                  onHide: (chat) => chatService.setHidden(
                                    userId: currentUserId,
                                    chatId: chat.id,
                                    hidden: true,
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white30),
      filled: true,
      fillColor: const Color(0xFF1A1A1A),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }
}

class _ChatRecordsList extends StatefulWidget {
  const _ChatRecordsList({
    required this.chats,
    required this.prefs,
    required this.currentUserId,
    required this.searchQuery,
    required this.filter,
    required this.onOpen,
    required this.onMenu,
    required this.onHide,
  });

  final List<ChatRoom> chats;
  final Map<String, ChatPref> prefs;
  final String currentUserId;
  final String searchQuery;
  final List<ChatRoom> Function(
    List<ChatRoom>,
    Map<String, ChatPref>,
    String,
    Map<String, AppUser?>,
  ) filter;
  final void Function(ChatRoom chat, String title) onOpen;
  final void Function(
    ChatRoom chat,
    ChatPref pref,
  ) onMenu;
  final Future<void> Function(ChatRoom chat) onHide;

  @override
  State<_ChatRecordsList> createState() => _ChatRecordsListState();
}

class _ChatRecordsListState extends State<_ChatRecordsList> {
  Stream<List<AppUser?>>? _usersStream;
  String _idsKey = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureUserStream();
  }

  @override
  void didUpdateWidget(covariant _ChatRecordsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ensureUserStream();
  }

  List<String> get _otherIds {
    return widget.chats
        .map((c) => c.otherParticipantId(widget.currentUserId))
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
  }

  void _ensureUserStream() {
    final ids = _otherIds;
    final key = ids.join('|');
    if (key == _idsKey && _usersStream != null) return;
    _idsKey = key;
    _usersStream = ids.isEmpty
        ? Stream.value(const [])
        : _combineUsers(context.read<AuthService>(), ids);
  }

  @override
  Widget build(BuildContext context) {
    final otherIds = _otherIds;
    final typingEnabled = context.watch<SettingsService>().typingEnabled;

    if (otherIds.isEmpty) {
      return const Center(
        child: Text('Henuz kayit yok.', style: TextStyle(color: Colors.white38)),
      );
    }

    return StreamBuilder<List<AppUser?>>(
      stream: _usersStream,
      builder: (context, snapshot) {
        final users = <String, AppUser?>{};
        final list = snapshot.data ?? [];
        for (var i = 0; i < otherIds.length && i < list.length; i++) {
          users[otherIds[i]] = list[i];
        }

        final visible = widget.filter(
          widget.chats,
          widget.prefs,
          widget.currentUserId,
          users,
        );
        if (visible.isEmpty) {
          return Center(
            child: Text(
              widget.searchQuery.trim().isEmpty
                  ? 'Gosterilecek kayit yok.'
                  : 'Eslesen kayit yok.',
              style: const TextStyle(color: Colors.white38),
            ),
          );
        }

        return ListView.separated(
          itemCount: visible.length,
          separatorBuilder: (_, __) =>
              const Divider(height: 1, color: Color(0xFF1C1C1C)),
          itemBuilder: (context, index) {
            final chat = visible[index];
            final otherUserId = chat.otherParticipantId(widget.currentUserId);
            final otherUser = users[otherUserId];
            final title = otherUser?.email ??
                otherUser?.displayName ??
                'Kullanici';
            final pref = widget.prefs[chat.id] ?? ChatPref.empty(chat.id);
            final unread = chat.unreadFor(widget.currentUserId);

            return Dismissible(
              key: ValueKey(chat.id),
              direction: DismissDirection.endToStart,
              background: const ColoredBox(
                color: Color(0xFF3A1A1A),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: EdgeInsets.only(right: 20),
                    child: Icon(Icons.visibility_off_outlined, color: Colors.white54),
                  ),
                ),
              ),
              confirmDismiss: (_) async {
                await widget.onHide(chat);
                return false;
              },
              child: InkWell(
                onTap: () => widget.onOpen(chat, title),
                onLongPress: () => widget.onMenu(chat, pref),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: const Color(0xFF2A2A2A),
                        child: Text(
                          ChatFormat.initials(title),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  'Kayit',
                                  style: TextStyle(
                                    color: Colors.white38,
                                    fontSize: 11,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                                if (pref.pinned) ...[
                                  const SizedBox(width: 6),
                                  const Icon(Icons.push_pin, size: 12, color: Colors.white38),
                                ],
                                if (pref.muted) ...[
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.volume_off_outlined,
                                    size: 12,
                                    color: Colors.white38,
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.86),
                                fontSize: 15,
                                fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.w400,
                              ),
                            ),
                            const SizedBox(height: 2),
                            TickingBuilder(
                              interval: const Duration(seconds: 2),
                              builder: (_) {
                                final nowTyping =
                                    typingEnabled && chat.isOtherTyping(otherUserId);
                                return Text(
                                  nowTyping
                                      ? 'Yaziyor...'
                                      : (chat.lastMessage.isEmpty
                                          ? 'Kayit olusturuldu'
                                          : chat.lastMessage),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: nowTyping ? Colors.white54 : Colors.white38,
                                    fontSize: 13,
                                    fontStyle: nowTyping
                                        ? FontStyle.italic
                                        : FontStyle.normal,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            ChatFormat.listTime(chat.lastMessageAt),
                            style: const TextStyle(color: Colors.white30, fontSize: 12),
                          ),
                          if (unread > 0) ...[
                            const SizedBox(height: 6),
                            Container(
                              constraints: const BoxConstraints(minWidth: 20),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF3A3A3A),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                unread > 99 ? '99+' : '$unread',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Stream<List<AppUser?>> _combineUsers(AuthService auth, List<String> ids) {
    if (ids.isEmpty) return Stream.value(const []);
    return Stream.multi((controller) {
      final latest = List<AppUser?>.filled(ids.length, null);
      final subs = <StreamSubscription<AppUser?>>[];
      for (var i = 0; i < ids.length; i++) {
        subs.add(auth.watchUser(ids[i]).listen((user) {
          latest[i] = user;
          controller.add(List<AppUser?>.from(latest));
        }));
      }
      controller.onCancel = () {
        for (final sub in subs) {
          sub.cancel();
        }
      };
    });
  }
}

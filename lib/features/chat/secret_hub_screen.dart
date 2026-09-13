import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/admin_config.dart';
import '../../core/chat_format.dart';
import '../../models/chat_model.dart';
import '../../models/chat_pref_model.dart';
import '../../models/message_model.dart';
import '../../models/pending_thread_model.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/chat_service.dart';
import '../../services/settings_service.dart';
import '../chat/chat_screen.dart';
import '../chat/pending_chats_screen.dart';
import '../settings/admin_home_screen.dart';
import '../settings/settings_screen.dart';

class SecretHubScreen extends StatefulWidget {
  const SecretHubScreen({super.key, required this.onExitToCalculator});

  final VoidCallback onExitToCalculator;

  @override
  State<SecretHubScreen> createState() => _SecretHubScreenState();
}

class _SecretHubScreenState extends State<SecretHubScreen> {
  final _emailController = TextEditingController();
  final _searchController = TextEditingController();
  final _groupNameController = TextEditingController();
  final _groupEmailsController = TextEditingController();
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
    _groupNameController.dispose();
    _groupEmailsController.dispose();
    super.dispose();
  }

  Future<void> _openChatWithEmail([String? address]) async {
    final email = (address ?? _emailController.text).trim();
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
        otherUserName: user.visibleName,
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
    String? initialMessageId,
    bool isGroup = false,
    String? groupName,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          chatId: chatId,
          otherUserId: otherUserId,
          otherUserName: otherUserName,
          isGroup: isGroup,
          groupName: groupName,
          pendingEmail: pendingEmail,
          onExitToCalculator: widget.onExitToCalculator,
          initialMessageId: initialMessageId,
        ),
      ),
    );
  }

  Future<void> _showNewPersonDialog() async {
    _emailController.clear();
    final email = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF161616),
        title: const Text('Yeni kişi', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: _emailController,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          style: const TextStyle(color: Colors.white),
          decoration: _fieldDecoration('ornek@mail.com'),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, _emailController.text),
            child: const Text('Devam'),
          ),
        ],
      ),
    );
    if (email != null && email.trim().isNotEmpty && mounted) {
      await _openChatWithEmail(email);
      if (_error != null && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_error!)));
      }
    }
  }

  Future<void> _showNewGroupDialog() async {
    _groupNameController.clear();
    _groupEmailsController.clear();
    final input = await showDialog<({String name, String emails})>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF161616),
        title: const Text('Yeni grup', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _groupNameController,
                autofocus: true,
                maxLength: 80,
                style: const TextStyle(color: Colors.white),
                decoration: _fieldDecoration('Grup adı'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _groupEmailsController,
                minLines: 3,
                maxLines: 6,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: Colors.white),
                decoration: _fieldDecoration(
                  'Üye e-postaları (virgül veya yeni satır)',
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Siz otomatik eklenirsiniz. En az 2 kayıtlı kişi girin.',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, (
              name: _groupNameController.text,
              emails: _groupEmailsController.text,
            )),
            child: const Text('Oluştur'),
          ),
        ],
      ),
    );
    if (input == null || !mounted) return;
    await _createGroup(input.name, input.emails);
  }

  Future<void> _createGroup(String rawName, String rawEmails) async {
    final name = rawName.trim();
    final parsed = ChatService.parseGroupEmails(rawEmails);
    final myEmail =
        context.read<AuthService>().currentUser?.email?.trim().toLowerCase() ??
        '';
    final problems = <String>[];
    if (name.isEmpty) problems.add('Grup adı zorunludur.');
    if (parsed.invalid.isNotEmpty) {
      problems.add('Geçersiz adres: ${parsed.invalid.join(', ')}');
    }
    if (parsed.duplicates.isNotEmpty) {
      problems.add('Tekrarlanan adres: ${parsed.duplicates.join(', ')}');
    }
    if (parsed.emails.contains(myEmail)) {
      problems.add('Kendi e-postanızı eklemeyin; otomatik katılırsınız.');
    }
    final emails = parsed.emails.where((email) => email != myEmail).toList();
    if (emails.length < 2) {
      problems.add('En az 2 farklı kişi e-postası girin.');
    }
    if (emails.length > 19) {
      problems.add('Bir grupta siz dahil en fazla 20 katılımcı olabilir.');
    }
    if (problems.isNotEmpty) {
      _showError(problems.join('\n'));
      return;
    }

    setState(() => _isStarting = true);
    try {
      final auth = context.read<AuthService>();
      final chatService = context.read<ChatService>();
      final users = <AppUser>[];
      final missing = <String>[];
      for (final email in emails) {
        final user = await auth.findUserByEmail(email);
        if (user == null) {
          missing.add(email);
        } else {
          users.add(user);
        }
      }
      if (missing.isNotEmpty) {
        _showError('Kayıtlı olmayan adres: ${missing.join(', ')}');
        return;
      }
      final creatorId = auth.currentUser!.uid;
      final chatId = await chatService.createGroup(
        creatorId: creatorId,
        groupName: name,
        participantIds: users.map((user) => user.id).toList(),
      );
      if (!mounted) return;
      await _openChat(
        chatId: chatId,
        otherUserId: '',
        otherUserName: name,
        isGroup: true,
        groupName: name,
      );
    } catch (error) {
      _showError(
        error is ArgumentError
            ? error.message.toString()
            : 'Grup oluşturulamadı. Tekrar deneyin.',
      );
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 6)),
    );
  }

  Future<void> _showCreateMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF161616),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_add_alt, color: Colors.white70),
              title: const Text(
                'Yeni kişi',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () => Navigator.pop(context, 'person'),
            ),
            ListTile(
              leading: const Icon(
                Icons.group_add_outlined,
                color: Colors.white70,
              ),
              title: const Text(
                'Yeni grup',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () => Navigator.pop(context, 'group'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'person') {
      await _showNewPersonDialog();
    } else if (choice == 'group') {
      await _showNewGroupDialog();
    }
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
    if (chat.isGroup) {
      await _openChat(
        chatId: chat.id,
        otherUserId: '',
        otherUserName: chat.groupName,
        isGroup: true,
        groupName: chat.groupName,
      );
      return;
    }
    final other = otherId.isEmpty
        ? null
        : await authService.watchUser(otherId).first;
    if (!mounted) return;
    await _openChat(
      chatId: chat.id,
      otherUserId: otherId,
      otherUserName: other?.visibleName ?? 'Kayit',
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
                    stream: chat.isGroup || otherId.isEmpty
                        ? Stream.value(null)
                        : authService.watchUser(otherId),
                    builder: (context, snapshot) {
                      final user = snapshot.data;
                      final label = chat.isGroup
                          ? chat.groupName
                          : (user?.visibleName ?? 'Gizli kayıt');
                      return Text(
                        label,
                        style: const TextStyle(color: Colors.white70),
                      );
                    },
                  ),
                  subtitle: Text(
                    chat.lastMessage.isEmpty
                        ? 'Kayit gizlendi'
                        : chat.lastMessage,
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
        chat.groupName,
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
                  pref.muted
                      ? Icons.volume_up_outlined
                      : Icons.volume_off_outlined,
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
                leading: const Icon(
                  Icons.visibility_off_outlined,
                  color: Colors.white70,
                ),
                title: const Text(
                  'Gizle',
                  style: TextStyle(color: Colors.white70),
                ),
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
                leading: const Icon(
                  Icons.delete_outline,
                  color: Color(0xFFFF8A80),
                ),
                title: const Text(
                  'Sil',
                  style: TextStyle(color: Color(0xFFFF8A80)),
                ),
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
      floatingActionButton: FloatingActionButton(
        tooltip: 'Yeni sohbet',
        backgroundColor: const Color(0xFFEEEEEE),
        foregroundColor: const Color(0xFF111111),
        onPressed: _isStarting ? null : _showCreateMenu,
        child: _isStarting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
      ),
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
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
            },
            icon: const Icon(
              Icons.settings_outlined,
              size: 18,
              color: Colors.white70,
            ),
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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(color: Colors.white),
              cursorColor: Colors.white54,
              decoration: _fieldDecoration('Sohbetlerde ara').copyWith(
                prefixIcon: const Icon(
                  Icons.search,
                  color: Colors.white30,
                  size: 20,
                ),
              ),
            ),
          ),
          const Divider(height: 1, color: Color(0xFF222222)),
          Expanded(
            child: StreamBuilder<List<PendingThread>>(
              stream: _pendingStream,
              initialData: chatService.cachedPendingSent(currentUserId),
              builder: (context, pendingSnapshot) {
                return StreamBuilder<List<ChatRoom>>(
                  stream: _chatsStream,
                  initialData: chatService.cachedUserChats(currentUserId),
                  builder: (context, chatSnapshot) {
                    return StreamBuilder<Map<String, ChatPref>>(
                      stream: _prefsStream,
                      initialData: chatService.cachedChatPrefs(currentUserId),
                      builder: (context, prefSnapshot) {
                        if (chatSnapshot.connectionState ==
                                ConnectionState.waiting &&
                            !chatSnapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white24,
                            ),
                          );
                        }

                        final chats = chatSnapshot.data ?? [];
                        final prefs = prefSnapshot.data ?? {};
                        final pending = pendingSnapshot.data ?? [];
                        final hidden = _hiddenChats(chats, prefs);
                        final query = _searchController.text
                            .trim()
                            .toLowerCase();
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
                                'Henüz sohbet yok.\nYeni bir sohbet için + düğmesine dokunun.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white38,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          );
                        }

                        return Column(
                          children: [
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
                            if (pending.isNotEmpty)
                              ListTile(
                                dense: true,
                                leading: const Icon(
                                  Icons.schedule_outlined,
                                  color: Colors.white38,
                                  size: 20,
                                ),
                                title: Text(
                                  'Bekleyen sohbetler (${pending.length})',
                                  style: const TextStyle(
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
                                      builder: (_) => PendingChatsScreen(
                                        threads: pending,
                                        onExitToCalculator:
                                            widget.onExitToCalculator,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            if (query.isNotEmpty)
                              _GlobalMessageHits(
                                query: query,
                                currentUserId: currentUserId,
                                onOpen: (chat, title, messageId) => _openChat(
                                  chatId: chat.id,
                                  otherUserId: chat.otherParticipantId(
                                    currentUserId,
                                  ),
                                  otherUserName: chat.isGroup
                                      ? chat.groupName
                                      : title,
                                  isGroup: chat.isGroup,
                                  groupName: chat.groupName,
                                  initialMessageId: messageId,
                                ),
                              ),
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
                                    otherUserId: chat.isGroup
                                        ? ''
                                        : chat.otherParticipantId(
                                            currentUserId,
                                          ),
                                    otherUserName: title,
                                    isGroup: chat.isGroup,
                                    groupName: chat.groupName,
                                    pendingEmail: title.contains('@')
                                        ? title
                                        : null,
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
  )
  filter;
  final void Function(ChatRoom chat, String title) onOpen;
  final void Function(ChatRoom chat, ChatPref pref) onMenu;
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
        .where((chat) => !chat.isGroup)
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
        : context.read<AuthService>().watchUsers(ids);
  }

  @override
  Widget build(BuildContext context) {
    final otherIds = _otherIds;
    final typingEnabled = context.watch<SettingsService>().typingEnabled;

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
            final title = chat.isGroup
                ? (chat.groupName.isEmpty ? 'Adsız grup' : chat.groupName)
                : (otherUser?.visibleName ?? 'Kullanıcı');
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
                    child: Icon(
                      Icons.visibility_off_outlined,
                      color: Colors.white54,
                    ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
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
                                Text(
                                  chat.isGroup ? 'Grup' : 'Kayıt',
                                  style: TextStyle(
                                    color: Colors.white38,
                                    fontSize: 11,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                                if (pref.pinned) ...[
                                  const SizedBox(width: 6),
                                  const Icon(
                                    Icons.push_pin,
                                    size: 12,
                                    color: Colors.white38,
                                  ),
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
                                fontWeight: unread > 0
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Builder(
                              builder: (_) {
                                final nowTyping =
                                    !chat.isGroup &&
                                    typingEnabled &&
                                    chat.isOtherTyping(otherUserId);
                                return Text(
                                  nowTyping
                                      ? 'Yaziyor...'
                                      : (chat.lastMessage.isEmpty
                                            ? 'Kayit olusturuldu'
                                            : chat.lastMessage),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: nowTyping
                                        ? Colors.white54
                                        : Colors.white38,
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
                            style: const TextStyle(
                              color: Colors.white30,
                              fontSize: 12,
                            ),
                          ),
                          if (unread > 0) ...[
                            const SizedBox(height: 6),
                            Container(
                              constraints: const BoxConstraints(minWidth: 20),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
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
}

class _GlobalMessageHits extends StatelessWidget {
  const _GlobalMessageHits({
    required this.query,
    required this.currentUserId,
    required this.onOpen,
  });

  final String query;
  final String currentUserId;
  final void Function(ChatRoom chat, String title, String messageId) onOpen;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<({ChatRoom chat, ChatMessage message})>>(
      future: context.read<ChatService>().searchAllChats(
        userId: currentUserId,
        query: query,
      ),
      builder: (context, snapshot) {
        final hits = snapshot.data ?? const [];
        if (hits.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Mesajlarda',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
            ...hits.take(12).map((hit) {
              return ListTile(
                dense: true,
                title: Text(
                  hit.message.preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                subtitle: Text(
                  ChatFormat.eventDateTime(hit.message.createdAt),
                  style: const TextStyle(color: Colors.white30, fontSize: 11),
                ),
                onTap: () => onOpen(hit.chat, 'Sohbet', hit.message.id),
              );
            }),
          ],
        );
      },
    );
  }
}

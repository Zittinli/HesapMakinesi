import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/chat_format.dart';
import '../../models/auth_event_model.dart';
import '../../models/user_model.dart';
import '../../models/chat_model.dart';
import '../../services/auth_log_service.dart';
import '../../services/auth_service.dart';
import '../../services/chat_service.dart';
import '../chat/secret_hub_screen.dart';
import 'admin_reports_screen.dart';

class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({
    super.key,
    required this.onExitToCalculator,
  });

  final VoidCallback onExitToCalculator;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: const Color(0xFF0B0B0B),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0B0B0B),
          foregroundColor: Colors.white70,
          elevation: 0,
          title: const Text(
            'Yönetim',
            style: TextStyle(fontWeight: FontWeight.w400),
          ),
          leading: IconButton(
            tooltip: 'Hesap makinesine dön',
            icon: const Icon(Icons.close),
            onPressed: onExitToCalculator,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SecretHubScreen(
                      onExitToCalculator: onExitToCalculator,
                    ),
                  ),
                );
              },
              child: const Text(
                'Sohbetler',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            IconButton(
              tooltip: 'Çıkış',
              icon: const Icon(Icons.logout, size: 20),
              onPressed: () => context.read<AuthService>().signOut(),
            ),
          ],
          bottom: const TabBar(
            indicatorColor: Colors.white70,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white38,
            tabs: [
              Tab(text: 'Bildirilenler'),
              Tab(text: 'Girişler'),
              Tab(text: 'Kullanıcılar'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            AdminReportsList(),
            _AuthEventsList(),
            _UsersList(),
          ],
        ),
      ),
    );
  }
}

class _AuthEventsList extends StatelessWidget {
  const _AuthEventsList();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AuthEvent>>(
      stream: context.read<AuthLogService>().watchEvents(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Giriş kayıtları okunamadı. Yönetici oturumunu yenile.\n${snapshot.error}',
                style: const TextStyle(color: Colors.white38),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white24),
          );
        }
        final events = snapshot.data!;
        if (events.isEmpty) {
          return const Center(
            child: Text(
              'Henüz giriş kaydı yok.',
              style: TextStyle(color: Colors.white38, height: 1.5),
              textAlign: TextAlign.center,
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          itemCount: events.length,
          separatorBuilder: (_, __) =>
              const Divider(color: Color(0xFF222222), height: 1),
          itemBuilder: (context, index) {
            final event = events[index];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                event.email.isEmpty ? '(e-posta yok)' : event.email,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              subtitle: Text(
                [
                  event.label,
                  if (event.errorCode.isNotEmpty) event.errorCode,
                ].join(' · '),
                style: TextStyle(
                  color: event.success
                      ? Colors.white38
                      : const Color(0xFFFF8A80),
                  fontSize: 12,
                ),
              ),
              trailing: Text(
                ChatFormat.eventDateTime(event.createdAt),
                style: const TextStyle(color: Colors.white30, fontSize: 11),
              ),
            );
          },
        );
      },
    );
  }
}

class _UsersList extends StatelessWidget {
  const _UsersList();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AppUser>>(
      stream: context.read<AuthService>().watchAllUsers(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Kullanıcılar okunamadı.\n${snapshot.error}',
              style: const TextStyle(color: Colors.white38),
              textAlign: TextAlign.center,
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white24),
          );
        }
        final users = snapshot.data!;
        if (users.isEmpty) {
          return const Center(
            child: Text(
              'Henüz kullanıcı yok.',
              style: TextStyle(color: Colors.white38),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          itemCount: users.length,
          separatorBuilder: (_, __) =>
              const Divider(color: Color(0xFF222222), height: 1),
          itemBuilder: (context, index) {
            final user = users[index];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                user.visibleName,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              subtitle: Text(
                [
                  user.email,
                  user.isOnline
                      ? 'Çevrimiçi'
                      : 'Son: ${ChatFormat.eventDateTime(user.lastSeen)}',
                ].join('\n'),
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
              isThreeLine: true,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _AdminUserDetails(user: user),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _AdminUserChats {
  const _AdminUserChats({required this.chats, required this.peers});

  final List<ChatRoom> chats;
  final Map<String, AppUser> peers;
}

class _AdminUserDetails extends StatefulWidget {
  const _AdminUserDetails({required this.user});

  final AppUser user;

  @override
  State<_AdminUserDetails> createState() => _AdminUserDetailsState();
}

class _AdminUserDetailsState extends State<_AdminUserDetails> {
  late final Future<_AdminUserChats> _loadFuture = _load();

  Future<_AdminUserChats> _load() async {
    final chatService = context.read<ChatService>();
    final auth = context.read<AuthService>();
    final chats = await chatService.chatsForUser(widget.user.id);
    final ids = <String>{};
    for (final chat in chats) {
      ids.addAll(chat.participants.where((id) => id != widget.user.id));
    }
    final peers = <String, AppUser>{};
    for (final id in ids) {
      final other = await auth.fetchUser(id);
      if (other != null) peers[id] = other;
    }
    return _AdminUserChats(chats: chats, peers: peers);
  }

  String _chatTitle(ChatRoom chat, Map<String, AppUser> peers) {
    if (chat.isGroup) {
      return chat.groupName.trim().isEmpty ? 'Grup' : chat.groupName.trim();
    }
    final otherId = chat.otherParticipantId(widget.user.id);
    return peers[otherId]?.visibleName ?? otherId;
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B0B),
        foregroundColor: Colors.white70,
        title: const Text('Kişi ayrıntıları'),
      ),
      body: FutureBuilder<_AdminUserChats>(
        future: _loadFuture,
        builder: (context, snapshot) {
          final chats = snapshot.data?.chats ?? const <ChatRoom>[];
          final peers = snapshot.data?.peers ?? const <String, AppUser>{};
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Text(
                user.visibleName,
                style: const TextStyle(color: Colors.white, fontSize: 20),
              ),
              const SizedBox(height: 8),
              Text(user.email, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 8),
              Text(
                user.isOnline
                    ? 'Çevrimiçi'
                    : 'Son aktiflik: ${ChatFormat.eventDateTime(user.lastSeen)}',
                style: const TextStyle(color: Colors.white54),
              ),
              Text(
                'Kayıt: ${ChatFormat.eventDateTime(user.createdAt)}',
                style: const TextStyle(color: Colors.white38),
              ),
              const SizedBox(height: 20),
              const Text(
                'İletişime geçtiği sohbetler',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 8),
              if (snapshot.hasError)
                Text(
                  'Sohbetler okunamadı.\n${snapshot.error}',
                  style: const TextStyle(color: Color(0xFFFF8A80), height: 1.4),
                )
              else if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Center(
                    child: CircularProgressIndicator(color: Colors.white24),
                  ),
                )
              else if (chats.isEmpty)
                const Text(
                  'Sohbet bulunamadı.',
                  style: TextStyle(color: Colors.white38),
                )
              else
                ...chats.map((chat) {
                  final otherId = chat.otherParticipantId(user.id);
                  final other = peers[otherId];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      _chatTitle(chat, peers),
                      style: const TextStyle(color: Colors.white70),
                    ),
                    subtitle: Text(
                      chat.isGroup
                          ? '${chat.participants.length} kişi'
                          : (other?.email.isNotEmpty == true
                                ? other!.email
                                : otherId),
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/admin_config.dart';
import '../../core/chat_format.dart';
import '../../core/slide_from_right_route.dart';
import '../../core/staff_perms.dart';
import '../../models/auth_event_model.dart';
import '../../models/user_model.dart';
import '../../services/auth_log_service.dart';
import '../../services/auth_service.dart';
import '../chat/secret_hub_screen.dart';
import '../../widgets/profile_avatar.dart';
import 'admin_groups_tab.dart';
import 'admin_reports_screen.dart';
import 'admin_search_field.dart';
import 'admin_staff_tab.dart';
import 'admin_user_actions.dart';
import 'founder_media_screen.dart';

class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({
    super.key,
    required this.onExitToCalculator,
  });

  final VoidCallback onExitToCalculator;

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    final uid = auth.currentUser?.uid ?? '';
    return StreamBuilder<AppUser?>(
      stream: uid.isEmpty ? Stream.value(null) : auth.watchUser(uid),
      builder: (context, snapshot) {
        final me = snapshot.data;
        final founder = AdminConfig.isFounder(
          email: auth.currentUser?.email,
          userId: uid,
        );
        final perms = founder
            ? StaffPerm.all.toSet()
            : StaffPerm.normalize(me?.staffPerms ?? const []);
        final tabs = <_AdminTab>[
          if (perms.contains(StaffPerm.viewReports) ||
              perms.contains(StaffPerm.punishReports))
            _AdminTab(
              'Bildirilenler',
              AdminReportsList(canPunish: perms.contains(StaffPerm.punishReports)),
            ),
          if (perms.contains(StaffPerm.readLogs))
            const _AdminTab('Girişler', _AuthEventsList()),
          if (perms.contains(StaffPerm.viewUsers))
            _AdminTab(
              'Kullanıcılar',
              _UsersList(
                canPunish: perms.contains(StaffPerm.punishReports),
                canGrantPerms: founder,
              ),
            ),
          if (perms.contains(StaffPerm.viewGroups))
            _AdminTab(
              'Gruplar',
              AdminGroupsTab(
                canSeeMembers: perms.contains(StaffPerm.viewGroupMembers),
                canTimeout: perms.contains(StaffPerm.timeoutGroup),
                canPunish: perms.contains(StaffPerm.punishReports),
                canGrantPerms: founder,
              ),
            ),
          if (founder) const _AdminTab('Yetkiler', AdminStaffTab()),
        ];
        if (tabs.isEmpty) {
          return Scaffold(
            backgroundColor: const Color(0xFF0B0B0B),
            appBar: AppBar(
              backgroundColor: const Color(0xFF0B0B0B),
              foregroundColor: Colors.white70,
              title: const Text('Yönetim'),
            ),
            body: const Center(
              child: Text(
                'Bu hesapta yönetim yetkisi yok.',
                style: TextStyle(color: Colors.white38),
              ),
            ),
          );
        }
        return DefaultTabController(
          key: ValueKey(tabs.map((tab) => tab.title).join('|')),
          length: tabs.length,
          child: Scaffold(
            backgroundColor: const Color(0xFF0B0B0B),
            appBar: AppBar(
              backgroundColor: const Color(0xFF0B0B0B),
              foregroundColor: Colors.white70,
              elevation: 0,
              title: _FounderSevenTapTitle(
                enabled: founder,
                onUnlocked: () {
                  Navigator.of(context).push(
                    SlideFromRightPageRoute(
                      builder: (_) => const FounderMediaPeopleScreen(),
                    ),
                  );
                },
              ),
              leading: IconButton(
                tooltip: 'Hesap makinesine dön',
                icon: const Icon(Icons.close),
                onPressed: onExitToCalculator,
              ),
              actions: [
                IconButton(
                  tooltip: 'Sohbetler',
                  icon: const Icon(Icons.chat_bubble_outline, size: 20),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SecretHubScreen(
                          onExitToCalculator: onExitToCalculator,
                        ),
                      ),
                    );
                  },
                ),
                IconButton(
                  tooltip: 'Çıkış',
                  icon: const Icon(Icons.logout, size: 20),
                  onPressed: () => context.read<AuthService>().signOut(),
                ),
              ],
              bottom: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicatorColor: Colors.white70,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white38,
                labelPadding: const EdgeInsets.symmetric(horizontal: 14),
                labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                unselectedLabelStyle: const TextStyle(fontSize: 13),
                tabs: [for (final tab in tabs) Tab(text: tab.title, height: 40)],
              ),
            ),
            body: TabBarView(
              children: [for (final tab in tabs) tab.child],
            ),
          ),
        );
      },
    );
  }
}

class _AdminTab {
  const _AdminTab(this.title, this.child);
  final String title;
  final Widget child;
}

class _FounderSevenTapTitle extends StatefulWidget {
  const _FounderSevenTapTitle({
    required this.enabled,
    required this.onUnlocked,
  });

  final bool enabled;
  final VoidCallback onUnlocked;

  @override
  State<_FounderSevenTapTitle> createState() => _FounderSevenTapTitleState();
}

class _FounderSevenTapTitleState extends State<_FounderSevenTapTitle> {
  int _taps = 0;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  void _onTap() {
    if (!widget.enabled) return;
    _reset?.cancel();
    _taps += 1;
    if (_taps >= 7) {
      _taps = 0;
      widget.onUnlocked();
      return;
    }
    _reset = Timer(const Duration(seconds: 2), () {
      _taps = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onTap,
      behavior: HitTestBehavior.opaque,
      child: const Text(
        'Yönetim',
        style: TextStyle(fontWeight: FontWeight.w400),
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

class _UsersList extends StatefulWidget {
  const _UsersList({
    required this.canPunish,
    required this.canGrantPerms,
  });

  final bool canPunish;
  final bool canGrantPerms;

  @override
  State<_UsersList> createState() => _UsersListState();
}

class _UsersListState extends State<_UsersList> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

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
        final all = snapshot.data!;
        final users = all
            .where(
              (user) => adminSearchMatches(_search.text, [
                user.visibleName,
                user.email,
                user.id,
              ]),
            )
            .toList();
        return Column(
          children: [
            AdminSearchField(
              controller: _search,
              hint: 'Ad veya e-posta ara',
              onChanged: (_) => setState(() {}),
            ),
            Expanded(
              child: all.isEmpty
                  ? const Center(
                      child: Text(
                        'Henüz kullanıcı yok.',
                        style: TextStyle(color: Colors.white38),
                      ),
                    )
                  : users.isEmpty
                  ? const Center(
                      child: Text(
                        'Eşleşen kullanıcı yok.',
                        style: TextStyle(color: Colors.white38),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                      itemCount: users.length,
                      separatorBuilder: (_, __) =>
                          const Divider(color: Color(0xFF222222), height: 1),
                      itemBuilder: (context, index) {
                        final user = users[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: ProfileAvatar(
                            name: user.visibleName,
                            photoUrl: user.visiblePhotoUrl,
                            hidden: user.photoHidden,
                            radius: 20,
                          ),
                          title: Text(
                            user.visibleName,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            [
                              user.email,
                              user.isEffectivelyOnline()
                                  ? 'Çevrimiçi'
                                  : 'Son: ${ChatFormat.eventDateTime(user.lastSeen)}',
                            ].join('\n'),
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                          isThreeLine: true,
                          onTap: () => showAdminUserActions(
                            context,
                            user: user,
                            canPunish: widget.canPunish,
                            canGrantPerms: widget.canGrantPerms,
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

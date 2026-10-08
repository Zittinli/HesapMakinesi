import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/chat_format.dart';
import '../../models/chat_model.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/chat_service.dart';
import '../../services/moderation_service.dart';
import '../../widgets/profile_avatar.dart';
import 'admin_search_field.dart';
import 'admin_user_actions.dart';

class AdminGroupsTab extends StatefulWidget {
  const AdminGroupsTab({
    super.key,
    required this.canSeeMembers,
    required this.canTimeout,
    required this.canPunish,
    required this.canGrantPerms,
  });

  final bool canSeeMembers;
  final bool canTimeout;
  final bool canPunish;
  final bool canGrantPerms;

  @override
  State<AdminGroupsTab> createState() => _AdminGroupsTabState();
}

class _AdminGroupsTabState extends State<AdminGroupsTab> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ChatRoom>>(
      stream: context.read<ChatService>().watchAllGroups(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Gruplar okunamadı.\n${snapshot.error}',
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
        final groups = snapshot.data!;
        return StreamBuilder<List<AppUser>>(
          stream: context.read<AuthService>().watchAllUsers(),
          builder: (context, usersSnap) {
            final users = <String, AppUser>{
              for (final user in usersSnap.data ?? const <AppUser>[])
                user.id: user,
            };
            final filtered = groups.where((group) {
              final memberFields = [
                for (final id in group.participants) ...[
                  users[id]?.visibleName ?? '',
                  users[id]?.email ?? '',
                  id,
                ],
              ];
              return adminSearchMatches(_search.text, [
                group.groupName,
                group.id,
                ...memberFields,
              ]);
            }).toList();
            return Column(
              children: [
                AdminSearchField(
                  controller: _search,
                  hint: 'Grup veya kişi ara',
                  onChanged: (_) => setState(() {}),
                ),
                Expanded(
                  child: groups.isEmpty
                      ? const Center(
                          child: Text(
                            'Henüz grup yok.',
                            style: TextStyle(color: Colors.white38),
                          ),
                        )
                      : filtered.isEmpty
                      ? const Center(
                          child: Text(
                            'Eşleşen grup yok.',
                            style: TextStyle(color: Colors.white38),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const Divider(
                            color: Color(0xFF222222),
                            height: 1,
                          ),
                          itemBuilder: (context, index) {
                            final group = filtered[index];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: ProfileAvatar(
                                name: group.groupName,
                                photoUrl: group.visibleGroupPhotoUrl,
                                radius: 20,
                              ),
                              title: Text(
                                group.groupName.trim().isEmpty
                                    ? 'Grup'
                                    : group.groupName,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: Text(
                                [
                                  '${group.participants.length} kişi',
                                  if (group.isGroupTimedOut()) 'timeout',
                                ].join(' · '),
                                style: TextStyle(
                                  color: group.isGroupTimedOut()
                                      ? const Color(0xFFFFCC80)
                                      : Colors.white38,
                                  fontSize: 12,
                                ),
                              ),
                              onTap: () => _openGroup(context, group),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openGroup(BuildContext context, ChatRoom group) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF161616),
      isScrollControlled: true,
      builder: (_) => _GroupSheet(
        group: group,
        canSeeMembers: widget.canSeeMembers,
        canTimeout: widget.canTimeout,
        canPunish: widget.canPunish,
        canGrantPerms: widget.canGrantPerms,
      ),
    );
  }
}

class _GroupSheet extends StatelessWidget {
  const _GroupSheet({
    required this.group,
    required this.canSeeMembers,
    required this.canTimeout,
    required this.canPunish,
    required this.canGrantPerms,
  });

  final ChatRoom group;
  final bool canSeeMembers;
  final bool canTimeout;
  final bool canPunish;
  final bool canGrantPerms;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ChatRoom?>(
      stream: context.read<ChatService>().watchChat(group.id),
      builder: (context, snapshot) {
        final live = snapshot.data ?? group;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.75,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  live.groupName,
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                ),
                Text(
                  '${live.participants.length} kişi · ${ChatFormat.eventDateTime(live.createdAt ?? live.lastMessageAt)}',
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
                if (live.isGroupTimedOut())
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Timeout: ${ChatFormat.eventDateTime(live.groupTimeoutUntil)}',
                      style: const TextStyle(
                        color: Color(0xFFFFCC80),
                        fontSize: 12,
                      ),
                    ),
                  ),
                if (canTimeout)
                  Theme(
                    data: Theme.of(context).copyWith(
                      dividerColor: Colors.transparent,
                    ),
                    child: ExpansionTile(
                      initiallyExpanded: false,
                      tilePadding: EdgeInsets.zero,
                      iconColor: Colors.white38,
                      collapsedIconColor: Colors.white24,
                      title: const Text(
                        'Timeout',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _timeoutChip(
                                context,
                                live,
                                '1 saat',
                                const Duration(hours: 1),
                              ),
                              _timeoutChip(
                                context,
                                live,
                                '24 saat',
                                const Duration(hours: 24),
                              ),
                              _timeoutChip(
                                context,
                                live,
                                '7 gün',
                                const Duration(days: 7),
                              ),
                              ActionChip(
                                label: const Text('Timeout kaldır'),
                                onPressed: () => _timeout(
                                  context,
                                  live,
                                  null,
                                  'Timeout kaldırıldı.',
                                ),
                                backgroundColor: const Color(0xFF1A1A1A),
                                labelStyle: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                if (canSeeMembers) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Üyeler',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: StreamBuilder<List<AppUser?>>(
                      stream: context.read<AuthService>().watchUsers(
                            live.participants,
                          ),
                      builder: (context, usersSnap) {
                        final users = (usersSnap.data ?? const <AppUser?>[])
                            .whereType<AppUser>()
                            .toList();
                        return ListView.builder(
                          shrinkWrap: true,
                          itemCount: users.length,
                          itemBuilder: (context, index) {
                            final user = users[index];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: ProfileAvatar(
                                name: user.visibleName,
                                photoUrl: user.visiblePhotoUrl,
                                hidden: user.photoHidden,
                                radius: 18,
                              ),
                              title: Text(
                                user.visibleName,
                                style: const TextStyle(color: Colors.white70),
                              ),
                              subtitle: Text(
                                user.email,
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 12,
                                ),
                              ),
                              onTap: () => showAdminUserActions(
                                context,
                                user: user,
                                canPunish: canPunish,
                                canGrantPerms: canGrantPerms,
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _timeoutChip(
    BuildContext context,
    ChatRoom group,
    String label,
    Duration timeout,
  ) {
    return ActionChip(
      label: Text(label),
      onPressed: () => _timeout(context, group, timeout, '$label uygulandı.'),
      backgroundColor: const Color(0xFF1A1A1A),
      labelStyle: const TextStyle(color: Colors.white70, fontSize: 12),
    );
  }

  Future<void> _timeout(
    BuildContext context,
    ChatRoom group,
    Duration? timeout,
    String ok,
  ) async {
    try {
      await context.read<ModerationService>().timeoutGroup(
            chatId: group.id,
            timeout: timeout,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok)));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }
}

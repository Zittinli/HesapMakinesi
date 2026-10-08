import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/admin_config.dart';
import '../../core/chat_format.dart';
import '../../core/staff_perms.dart';
import '../../models/chat_model.dart';
import '../../models/moderation_model.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/chat_service.dart';
import '../../services/moderation_service.dart';
import '../../widgets/profile_avatar.dart';
import 'staff_perm_toggles.dart';

Future<void> showAdminUserActions(
  BuildContext context, {
  required AppUser user,
  required bool canPunish,
  required bool canGrantPerms,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => AdminUserDetailsScreen(
        user: user,
        canPunish: canPunish,
        canGrantPerms: canGrantPerms,
      ),
    ),
  );
}

class AdminUserDetailsScreen extends StatefulWidget {
  const AdminUserDetailsScreen({
    super.key,
    required this.user,
    required this.canPunish,
    required this.canGrantPerms,
  });

  final AppUser user;
  final bool canPunish;
  final bool canGrantPerms;

  @override
  State<AdminUserDetailsScreen> createState() => _AdminUserDetailsScreenState();
}

class _AdminUserDetailsScreenState extends State<AdminUserDetailsScreen> {
  late final Future<_AdminUserChats> _chatsFuture = _loadChats();

  bool get _founder =>
      AdminConfig.isFounder(email: widget.user.email, userId: widget.user.id);

  Future<_AdminUserChats> _loadChats() async {
    final chatService = context.read<ChatService>();
    final auth = context.read<AuthService>();
    final chats = await chatService.chatsForUser(widget.user.id);
    chats.sort((a, b) {
      final at = a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bt = b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bt.compareTo(at);
    });
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
    final auth = context.read<AuthService>();
    return StreamBuilder<AppUser?>(
      stream: auth.watchUser(widget.user.id),
      builder: (context, snapshot) {
        final live = snapshot.data ?? widget.user;
        return Scaffold(
          backgroundColor: const Color(0xFF0B0B0B),
          appBar: AppBar(
            backgroundColor: const Color(0xFF0B0B0B),
            foregroundColor: Colors.white70,
            title: const Text('Kişi'),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Row(
                children: [
                  ProfileAvatar(
                    name: live.visibleName,
                    photoUrl: live.visiblePhotoUrl,
                    hidden: live.photoHidden,
                    radius: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          live.visibleName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          live.email,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                live.isEffectivelyOnline()
                    ? 'Çevrimiçi'
                    : 'Son: ${ChatFormat.eventDateTime(live.lastSeen)}',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
              StreamBuilder<ModerationStatus>(
                stream: context.read<ModerationService>().watchRestriction(
                      userId: live.id,
                      email: live.email,
                    ),
                builder: (context, restriction) {
                  final status = restriction.data;
                  if (status == null ||
                      (!status.isRestricted() && !status.hideProfilePhoto)) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      [
                        if (status.isRestricted()) status.label,
                        if (status.hideProfilePhoto || live.photoHidden)
                          'Profil fotoğrafı gizli.',
                      ].join(' '),
                      style: const TextStyle(
                        color: Color(0xFFFFCC80),
                        fontSize: 12,
                      ),
                    ),
                  );
                },
              ),
              if (_founder)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Text(
                    'Kurucu yönetici. Ceza ve yetki değişmez.',
                    style: TextStyle(color: Color(0xFFFFCC80), fontSize: 12),
                  ),
                )
              else ...[
                if (widget.canPunish)
                  _Section(
                    title: 'Cezalar',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _chip(context, live, '1 saat', const Duration(hours: 1)),
                        _chip(context, live, '24 saat', const Duration(hours: 24)),
                        _chip(context, live, '7 gün', const Duration(days: 7)),
                        _chip(context, live, 'Kalıcı ban', null, permanent: true),
                        ActionChip(
                          label: const Text('Cezayı kaldır'),
                          onPressed: () => _run(
                            context,
                            () => context.read<ModerationService>().clearPenalty(
                                  userId: live.id,
                                  email: live.email,
                                ),
                            'Ceza kaldırıldı.',
                          ),
                          backgroundColor: const Color(0xFF1A1A1A),
                          labelStyle: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                        ActionChip(
                          label: Text(
                            live.photoHidden
                                ? 'Fotoğrafı göster'
                                : 'Fotoğrafı gizle',
                          ),
                          onPressed: () => _run(
                            context,
                            () => context
                                .read<ModerationService>()
                                .setProfilePhotoHidden(
                                  userId: live.id,
                                  email: live.email,
                                  hidden: !live.photoHidden,
                                ),
                            live.photoHidden
                                ? 'Fotoğraf gösterime alındı.'
                                : 'Fotoğraf gizlendi.',
                          ),
                          backgroundColor: const Color(0xFF1A1A1A),
                          labelStyle: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (widget.canGrantPerms)
                  _Section(
                    title: 'Yetkiler',
                    child: StaffPermToggles(
                      perms: live.staffPerms,
                      onToggle: (perm) {
                        final next = StaffPerm.toggle(live.staffPerms, perm);
                        _run(
                          context,
                          () => context.read<AuthService>().setStaffPerms(
                                userId: live.id,
                                email: live.email,
                                perms: next,
                              ),
                          'Yetki güncellendi.',
                        );
                      },
                    ),
                  ),
              ],
              const SizedBox(height: 20),
              const Text(
                'İletişime geçtiği sohbetler',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 8),
              FutureBuilder<_AdminUserChats>(
                future: _chatsFuture,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Text(
                      'Sohbetler okunamadı.\n${snapshot.error}',
                      style: const TextStyle(
                        color: Color(0xFFFF8A80),
                        height: 1.4,
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Center(
                        child: CircularProgressIndicator(color: Colors.white24),
                      ),
                    );
                  }
                  final chats = snapshot.data!.chats;
                  final peers = snapshot.data!.peers;
                  if (chats.isEmpty) {
                    return const Text(
                      'Sohbet bulunamadı.',
                      style: TextStyle(color: Colors.white38),
                    );
                  }
                  return Column(
                    children: [
                      for (final chat in chats)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: ProfileAvatar(
                            name: _chatTitle(chat, peers),
                            photoUrl: chat.isGroup
                                ? chat.visibleGroupPhotoUrl
                                : peers[chat.otherParticipantId(live.id)]
                                    ?.visiblePhotoUrl,
                            hidden: chat.isGroup
                                ? false
                                : (peers[chat.otherParticipantId(live.id)]
                                        ?.photoHidden ??
                                    false),
                            radius: 18,
                          ),
                          title: Text(
                            _chatTitle(chat, peers),
                            style: const TextStyle(color: Colors.white70),
                          ),
                          subtitle: Text(
                            chat.isGroup
                                ? '${chat.participants.length} kişi'
                                : (peers[chat.otherParticipantId(live.id)]
                                        ?.email ??
                                    ''),
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _chip(
    BuildContext context,
    AppUser live,
    String label,
    Duration? timeout, {
    bool permanent = false,
  }) {
    return ActionChip(
      label: Text(label),
      onPressed: () => _run(
        context,
        () => context.read<ModerationService>().applyPenalty(
              userId: live.id,
              email: live.email,
              reason: label,
              timeout: timeout,
              permanent: permanent,
            ),
        '$label uygulandı.',
      ),
      backgroundColor: permanent ? const Color(0xFF3A1A1A) : const Color(0xFF1A1A1A),
      labelStyle: TextStyle(
        color: permanent ? const Color(0xFFFF8A80) : Colors.white70,
        fontSize: 12,
      ),
    );
  }

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
    String ok,
  ) async {
    try {
      await action();
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

class _AdminUserChats {
  const _AdminUserChats({required this.chats, required this.peers});

  final List<ChatRoom> chats;
  final Map<String, AppUser> peers;
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: false,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        iconColor: Colors.white38,
        collapsedIconColor: Colors.white24,
        title: Text(
          title,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        children: [child],
      ),
    );
  }
}

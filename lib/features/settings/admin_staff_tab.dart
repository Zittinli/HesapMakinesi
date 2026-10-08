import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/admin_config.dart';
import '../../core/staff_perms.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../widgets/profile_avatar.dart';
import 'admin_search_field.dart';
import 'admin_user_actions.dart';

class AdminStaffTab extends StatefulWidget {
  const AdminStaffTab({super.key});

  @override
  State<AdminStaffTab> createState() => _AdminStaffTabState();
}

class _AdminStaffTabState extends State<AdminStaffTab> {
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
              'Yetkililer okunamadı.\n${snapshot.error}',
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
        final staff = snapshot.data!
            .where(
              (user) =>
                  !AdminConfig.isFounder(email: user.email, userId: user.id) &&
                  StaffPerm.normalize(user.staffPerms).isNotEmpty,
            )
            .where(
              (user) => adminSearchMatches(_search.text, [
                user.visibleName,
                user.email,
                ...StaffPerm.normalize(user.staffPerms).map(StaffPerm.labelOf),
              ]),
            )
            .toList();
        final hasAnyStaff = snapshot.data!.any(
          (user) =>
              !AdminConfig.isFounder(email: user.email, userId: user.id) &&
              StaffPerm.normalize(user.staffPerms).isNotEmpty,
        );
        return Column(
          children: [
            AdminSearchField(
              controller: _search,
              hint: 'Yetkili kişi ara',
              onChanged: (_) => setState(() {}),
            ),
            Expanded(
              child: !hasAnyStaff
                  ? const Center(
                      child: Text(
                        'Yetkisi olan kullanıcı yok. Kullanıcılar listesinden yetki ver.',
                        style: TextStyle(color: Colors.white38, height: 1.5),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : staff.isEmpty
                  ? const Center(
                      child: Text(
                        'Eşleşen yetkili yok.',
                        style: TextStyle(color: Colors.white38),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                      itemCount: staff.length,
                      separatorBuilder: (_, __) => const Divider(
                        color: Color(0xFF222222),
                        height: 1,
                      ),
                      itemBuilder: (context, index) {
                        final user = staff[index];
                        final perms = StaffPerm.normalize(user.staffPerms);
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
                            perms.map(StaffPerm.labelOf).join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                          onTap: () => showAdminUserActions(
                            context,
                            user: user,
                            canPunish: true,
                            canGrantPerms: true,
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

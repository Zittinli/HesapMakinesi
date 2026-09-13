import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/chat_format.dart';
import '../../models/chat_model.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/chat_service.dart';

class GroupDetailsScreen extends StatefulWidget {
  const GroupDetailsScreen({super.key, required this.chatId});

  final String chatId;

  @override
  State<GroupDetailsScreen> createState() => _GroupDetailsScreenState();
}

class _GroupDetailsScreenState extends State<GroupDetailsScreen> {
  bool _busy = false;

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', ''))),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rename(ChatRoom chat) async {
    var value = chat.groupName;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF161616),
        title: const Text(
          'Grubun adını değiştir',
          style: TextStyle(color: Colors.white),
        ),
        content: TextFormField(
          initialValue: value,
          autofocus: true,
          maxLength: 80,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Grup adı',
            labelStyle: TextStyle(color: Colors.white54),
          ),
          onChanged: (text) => value = text,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      () => context.read<ChatService>().renameGroup(
        chatId: chat.id,
        groupName: value,
      ),
    );
  }

  Future<void> _addMembers(ChatRoom chat) async {
    var value = '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF161616),
        title: const Text(
          'Gruba kişi ekle',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          keyboardType: TextInputType.emailAddress,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'E-postaları virgül veya satırla ayırın',
            hintStyle: TextStyle(color: Colors.white38),
          ),
          onChanged: (text) => value = text,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Ekle'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final parsed = ChatService.parseGroupEmails(value);
    if (parsed.invalid.isNotEmpty || parsed.emails.isEmpty) {
      _showError(
        parsed.invalid.isNotEmpty
            ? 'Geçersiz adres: ${parsed.invalid.join(', ')}'
            : 'En az bir e-posta girin.',
      );
      return;
    }
    await _run(() async {
      final auth = context.read<AuthService>();
      final chatService = context.read<ChatService>();
      final users = <AppUser>[];
      final missing = <String>[];
      for (final email in parsed.emails) {
        final user = await auth.findUserByEmail(email);
        if (user == null) {
          missing.add(email);
        } else if (!chat.participants.contains(user.id)) {
          users.add(user);
        }
      }
      if (missing.isNotEmpty) {
        throw StateError('Kayıtlı olmayan adres: ${missing.join(', ')}');
      }
      if (users.isEmpty) {
        throw StateError('Girilen kişilerin tamamı zaten grupta.');
      }
      await chatService.addMembers(
        chatId: chat.id,
        memberIds: users.map((user) => user.id),
      );
    });
  }

  Future<void> _setAdmin(ChatRoom chat, AppUser user, bool makeAdmin) async {
    await _run(
      () => context.read<ChatService>().setGroupAdmin(
        chatId: chat.id,
        memberId: user.id,
        isAdmin: makeAdmin,
      ),
    );
  }

  Future<void> _removeMember(ChatRoom chat, AppUser user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF161616),
        content: Text(
          '${user.visibleName} gruptan çıkarılsın mı?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Çıkar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      () => context.read<ChatService>().removeMember(
        chatId: chat.id,
        memberId: user.id,
      ),
    );
  }

  Future<void> _leave(ChatRoom chat, String uid) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF161616),
        content: const Text(
          'Gruptan ayrılmak istediğinize emin misiniz?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Ayrıl'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() async {
      await context.read<ChatService>().leaveGroup(
        chatId: chat.id,
        userId: uid,
      );
      if (mounted) Navigator.pop(context, true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    final uid = auth.currentUser!.uid;
    return StreamBuilder<ChatRoom?>(
      stream: context.read<ChatService>().watchChat(widget.chatId),
      builder: (context, chatSnapshot) {
        final chat = chatSnapshot.data;
        if (chat == null) {
          return const Scaffold(
            backgroundColor: Color(0xFF0B0B0B),
            body: Center(
              child: CircularProgressIndicator(color: Colors.white24),
            ),
          );
        }
        final canManage = chat.isAdmin(uid);
        return StreamBuilder<List<AppUser?>>(
          stream: auth.watchUsers(chat.participants),
          builder: (context, usersSnapshot) {
            final users = usersSnapshot.data ?? const <AppUser?>[];
            return Scaffold(
              backgroundColor: const Color(0xFF0B0B0B),
              appBar: AppBar(
                backgroundColor: const Color(0xFF0B0B0B),
                foregroundColor: Colors.white70,
                title: const Text('Grup ayrıntıları'),
                actions: [
                  if (canManage)
                    IconButton(
                      tooltip: 'Grup adını değiştir',
                      onPressed: _busy ? null : () => _rename(chat),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  if (canManage)
                    IconButton(
                      tooltip: 'Üye ekle',
                      onPressed: _busy ? null : () => _addMembers(chat),
                      icon: const Icon(Icons.person_add_alt),
                    ),
                ],
              ),
              body: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  Text(
                    chat.groupName,
                    style: const TextStyle(color: Colors.white, fontSize: 22),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Oluşturulma: ${ChatFormat.eventDateTime(chat.createdAt ?? chat.lastMessageAt)}',
                    style: const TextStyle(color: Colors.white38),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '${chat.participants.length} katılımcı',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...users.whereType<AppUser>().map((user) {
                    final admin = chat.isAdmin(user.id);
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFF242424),
                        child: Text(
                          user.visibleName.characters.first.toUpperCase(),
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                      title: Text(
                        user.visibleName,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      subtitle: Text(
                        user.email,
                        style: const TextStyle(color: Colors.white38),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (admin)
                            const Padding(
                              padding: EdgeInsets.only(right: 6),
                              child: Text(
                                'Yönetici',
                                style: TextStyle(
                                  color: Color(0xFF90CAF9),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          if (canManage && user.id != uid)
                            PopupMenuButton<String>(
                              color: const Color(0xFF161616),
                              onSelected: (action) {
                                if (action == 'admin') {
                                  _setAdmin(chat, user, !admin);
                                } else if (action == 'remove') {
                                  _removeMember(chat, user);
                                }
                              },
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  value: 'admin',
                                  child: Text(
                                    admin
                                        ? 'Yöneticilikten çıkar'
                                        : 'Yönetici yap',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                    ),
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'remove',
                                  child: Text(
                                    'Gruptan çıkar',
                                    style: TextStyle(color: Color(0xFFFF8A80)),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _leave(chat, uid),
                    icon: const Icon(Icons.exit_to_app),
                    label: const Text('Gruptan ayrıl'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFFF8A80),
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

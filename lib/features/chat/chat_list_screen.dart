import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/chat_service.dart';
import '../chat/chat_screen.dart';
import '../users/user_search_screen.dart';

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key, required this.onExitToCalculator});

  final VoidCallback onExitToCalculator;

  String _formatLastSeen(AppUser? user) {
    if (user == null) return '';
    if (user.isOnline) return 'Cevrimici';
    if (user.lastSeen == null) return 'Son gorulme bilinmiyor';
    return 'Son gorulme: ${DateFormat('dd.MM.yyyy HH:mm').format(user.lastSeen!)}';
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.read<AuthService>();
    final chatService = context.read<ChatService>();
    final currentUserId = authService.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sohbetler'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: onExitToCalculator,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const UserSearchScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => authService.signOut(),
          ),
        ],
      ),
      body: StreamBuilder(
        stream: chatService.watchUserChats(currentUserId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final chats = snapshot.data ?? [];
          if (chats.isEmpty) {
            return const Center(
              child: Text('Henuz sohbet yok. Yeni kisi arayin.'),
            );
          }

          return ListView.separated(
            itemCount: chats.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final chat = chats[index];
              final otherUserId = chat.otherParticipantId(currentUserId);

              return StreamBuilder<AppUser?>(
                stream: chat.isGroup
                    ? Stream.value(null)
                    : authService.watchUser(otherUserId),
                builder: (context, userSnapshot) {
                  final otherUser = userSnapshot.data;
                  final title = chat.isGroup
                      ? (chat.groupName.isEmpty ? 'Adsız grup' : chat.groupName)
                      : (otherUser?.displayName.isNotEmpty == true
                            ? otherUser!.displayName
                            : otherUser?.email ?? 'Kullanıcı');

                  return ListTile(
                    title: Text(title),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          chat.lastMessage.isEmpty
                              ? 'Sohbet baslatildi'
                              : chat.lastMessage,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (!chat.isGroup)
                          Text(
                            _formatLastSeen(otherUser),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                    trailing: chat.lastMessageAt != null
                        ? Text(
                            DateFormat('HH:mm').format(chat.lastMessageAt!),
                            style: Theme.of(context).textTheme.bodySmall,
                          )
                        : null,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            chatId: chat.id,
                            otherUserId: chat.isGroup ? '' : otherUserId,
                            otherUserName: title,
                            isGroup: chat.isGroup,
                            groupName: chat.groupName,
                            onExitToCalculator: onExitToCalculator,
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const UserSearchScreen()));
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

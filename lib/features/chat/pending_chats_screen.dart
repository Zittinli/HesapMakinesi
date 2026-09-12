import 'package:flutter/material.dart';

import '../../core/chat_format.dart';
import '../../models/pending_thread_model.dart';
import 'chat_screen.dart';

class PendingChatsScreen extends StatelessWidget {
  const PendingChatsScreen({
    super.key,
    required this.threads,
    required this.onExitToCalculator,
  });

  final List<PendingThread> threads;
  final VoidCallback onExitToCalculator;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B0B),
        foregroundColor: Colors.white70,
        title: const Text('Bekleyen sohbetler'),
      ),
      body: threads.isEmpty
          ? const Center(
              child: Text(
                'Bekleyen sohbet yok.',
                style: TextStyle(color: Colors.white38),
              ),
            )
          : ListView.separated(
              itemCount: threads.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: Color(0xFF1C1C1C)),
              itemBuilder: (context, index) {
                final item = threads[index];
                return ListTile(
                  textColor: Colors.white70,
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFF2A2A2A),
                    child: Text(
                      ChatFormat.initials(item.recipientEmail),
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
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
                  trailing: Text(
                    ChatFormat.listTime(item.lastMessageAt),
                    style: const TextStyle(color: Colors.white30, fontSize: 12),
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          chatId: '',
                          otherUserId: '',
                          otherUserName: item.recipientEmail,
                          pendingEmail: item.recipientEmail,
                          onExitToCalculator: onExitToCalculator,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

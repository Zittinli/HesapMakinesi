import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/chat_format.dart';
import '../../models/chat_model.dart';
import '../../models/chat_pref_model.dart';
import '../../models/starred_message.dart';
import '../../services/auth_service.dart';
import '../../services/chat_service.dart';
import '../../services/peer_profile_cache.dart';
import '../chat/chat_screen.dart';

class StarredMessagesScreen extends StatelessWidget {
  const StarredMessagesScreen({super.key, this.onExitToCalculator});

  final VoidCallback? onExitToCalculator;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B0B),
        foregroundColor: Colors.white70,
        elevation: 0,
        title: const Text(
          'Yıldızlı mesajlar',
          style: TextStyle(fontWeight: FontWeight.w400, letterSpacing: 0.4),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 24),
        children: [
          StarredMessageSection(
            showChatLabel: true,
            onOpen: (star) => openStarredMessage(
              context,
              star: star,
              onExitToCalculator: onExitToCalculator,
            ),
          ),
        ],
      ),
    );
  }
}

class StarredMessageSection extends StatelessWidget {
  const StarredMessageSection({
    super.key,
    required this.onOpen,
    this.onlyChatId,
    this.showChatLabel = false,
  });

  final void Function(StarredMessage star) onOpen;
  final String? onlyChatId;
  final bool showChatLabel;

  @override
  Widget build(BuildContext context) {
    final uid = context.read<AuthService>().currentUser?.uid ?? '';
    final chatService = context.read<ChatService>();
    if (uid.isEmpty) {
      return const SizedBox.shrink();
    }

    return StreamBuilder(
      stream: chatService.watchStarred(uid),
      builder: (context, starSnapshot) {
        return StreamBuilder(
          stream: chatService.watchChatPrefs(uid),
          builder: (context, prefSnapshot) {
            return StreamBuilder(
              stream: showChatLabel
                  ? chatService.watchUserChats(uid)
                  : Stream<List<ChatRoom>>.value(const []),
              builder: (context, chatSnapshot) {
                if (starSnapshot.hasError) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Yıldızlı mesajlar okunamadı.',
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                  );
                }
                if (starSnapshot.connectionState == ConnectionState.waiting &&
                    !starSnapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white24,
                        ),
                      ),
                    ),
                  );
                }
                final items = visibleStarredMessages(
                  stars: starSnapshot.data ?? const <StarredMessage>[],
                  prefs: prefSnapshot.data ?? const <String, ChatPref>{},
                  onlyChatId: onlyChatId,
                );

                if (items.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Yıldızlı mesaj yok.',
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                  );
                }

                final chats = {
                  for (final chat in chatSnapshot.data ?? const <ChatRoom>[])
                    chat.id: chat,
                };
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final star in items)
                      _StarredRow(
                        star: star,
                        label: showChatLabel
                            ? _chatLabel(chats[star.chatId], uid)
                            : '',
                        onOpen: () => onOpen(star),
                      ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  String _chatLabel(ChatRoom? chat, String uid) {
    if (chat == null) return '';
    if (chat.isGroup) {
      return chat.groupName.trim().isEmpty ? 'Grup' : chat.groupName.trim();
    }
    final otherId = chat.otherParticipantId(uid);
    return PeerProfileCache.instance.lookup(otherId)?.name ?? '';
  }
}

class _StarredRow extends StatelessWidget {
  const _StarredRow({
    required this.star,
    required this.label,
    required this.onOpen,
  });

  final StarredMessage star;
  final String label;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final when = ChatFormat.eventDateTime(star.createdAt);
    final subtitle = label.isEmpty ? when : '$label · $when';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const Icon(Icons.star, size: 14, color: Color(0xFFD0D0D0)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  star.preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Sohbette göster',
            onPressed: onOpen,
            icon: const Icon(Icons.chevron_right, color: Colors.white54),
          ),
        ],
      ),
    );
  }
}

Future<void> openStarredMessage(
  BuildContext context, {
  required StarredMessage star,
  VoidCallback? onExitToCalculator,
}) async {
  final auth = context.read<AuthService>();
  final chats = context.read<ChatService>();
  final uid = auth.currentUser?.uid ?? '';
  final chat = await chats.getChat(star.chatId);
  if (!context.mounted || chat == null) return;
  final otherId = chat.isGroup ? '' : chat.otherParticipantId(uid);
  final cached = PeerProfileCache.instance.lookup(otherId)?.name;
  final title = chat.isGroup
      ? (chat.groupName.trim().isEmpty ? 'Grup' : chat.groupName.trim())
      : (cached ?? 'Sohbet');
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ChatScreen(
        chatId: chat.id,
        otherUserId: otherId,
        otherUserName: title,
        isGroup: chat.isGroup,
        groupName: chat.groupName,
        initialMessageId: star.messageId,
        onExitToCalculator:
            onExitToCalculator ??
            () {
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
      ),
    ),
  );
}

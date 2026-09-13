import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/chat_format.dart';
import '../../core/ticking_builder.dart';
import '../../models/message_model.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.isRead,
    this.senderLabel,
    this.onLongPress,
    this.onMediaTap,
    this.highlighted = false,
  });

  final ChatMessage message;
  final bool isMine;
  final bool isRead;
  final String? senderLabel;
  final VoidCallback? onLongPress;
  final VoidCallback? onMediaTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final alignment = isMine ? Alignment.centerRight : Alignment.centerLeft;
    final color = highlighted
        ? const Color(0xFF4A3F22)
        : isMine
        ? const Color(0xFF2A2A2A)
        : const Color(0xFF161616);

    return Align(
      alignment: alignment,
      child: GestureDetector(
        onLongPress: onLongPress,
        onTap: message.hasMedia ? onMediaTap : null,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: highlighted
                  ? const Color(0xFFFFCC80)
                  : const Color(0xFF2C2C2C),
            ),
          ),
          child: Column(
            crossAxisAlignment: isMine
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              if (!isMine && (senderLabel ?? '').isNotEmpty) ...[
                Text(
                  senderLabel!,
                  style: const TextStyle(
                    color: Color(0xFF90CAF9),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
              ],
              if (message.replyToText != null &&
                  message.replyToText!.isNotEmpty)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111111),
                    borderRadius: BorderRadius.circular(8),
                    border: const Border(
                      left: BorderSide(color: Color(0xFF666666), width: 2),
                    ),
                  ),
                  child: Text(
                    message.replyToText!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
              if (message.hasMedia)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: message.type == MessageType.video
                      ? const _VideoThumb()
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: CachedNetworkImage(
                            imageUrl: message.mediaUrl!,
                            width: 180,
                            height: 180,
                            fit: BoxFit.cover,
                            memCacheWidth: 360,
                            memCacheHeight: 360,
                          ),
                        ),
                )
              else
                Text(
                  message.text,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
              const SizedBox(height: 4),
              if (message.expiresAt != null)
                TickingBuilder(
                  builder: (_) => _MessageStatus(
                    message: message,
                    isMine: isMine,
                    isRead: isRead,
                  ),
                )
              else
                _MessageStatus(
                  message: message,
                  isMine: isMine,
                  isRead: isRead,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageStatus extends StatelessWidget {
  const _MessageStatus({
    required this.message,
    required this.isMine,
    required this.isRead,
  });

  final ChatMessage message;
  final bool isMine;
  final bool isRead;

  @override
  Widget build(BuildContext context) {
    final ttl = message.remainingTtl();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (ttl != null) ...[
          Icon(
            Icons.timer_outlined,
            size: 12,
            color: ttl.inSeconds <= 3
                ? const Color(0xFFFF8A80)
                : Colors.white38,
          ),
          const SizedBox(width: 3),
          Text(
            '${ttl.inSeconds}s',
            style: TextStyle(
              color: ttl.inSeconds <= 3
                  ? const Color(0xFFFF8A80)
                  : Colors.white38,
              fontSize: 11,
            ),
          ),
          const SizedBox(width: 8),
        ],
        if (message.wasEdited) ...[
          const Text(
            'duzenlendi',
            style: TextStyle(color: Colors.white30, fontSize: 11),
          ),
          const SizedBox(width: 6),
        ],
        Text(
          ChatFormat.messageTime(message.createdAt),
          style: const TextStyle(color: Colors.white30, fontSize: 11),
        ),
        if (isMine) ...[
          const SizedBox(width: 4),
          Icon(
            isRead ? Icons.done_all : Icons.done,
            size: 14,
            color: isRead ? const Color(0xFF90CAF9) : Colors.white38,
          ),
        ],
      ],
    );
  }
}

class _VideoThumb extends StatelessWidget {
  const _VideoThumb();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      height: 120,
      decoration: BoxDecoration(
        color: const Color(0xFF090909),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.play_circle_fill, color: Colors.white70, size: 46),
          SizedBox(height: 6),
          Text('Video', style: TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      ),
    );
  }
}

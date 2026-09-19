import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/chat_format.dart';
import '../../core/chat_links.dart';
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
    this.onReplyTap,
    this.highlighted = false,
    this.pending = false,
  });

  final ChatMessage message;
  final bool isMine;
  final bool isRead;
  final String? senderLabel;
  final VoidCallback? onLongPress;
  final VoidCallback? onMediaTap;
  final VoidCallback? onReplyTap;
  final bool highlighted;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final alignment = isMine ? Alignment.centerRight : Alignment.centerLeft;
    final color = highlighted
        ? const Color(0xFF4A3F22)
        : isMine
        ? const Color(0xFF2A2A2A)
        : const Color(0xFF161616);
    final links = ChatLinks.extract(message.text);

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
                GestureDetector(
                  onTap: onReplyTap,
                  child: Container(
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
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              if (message.hasMedia)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: message.type == MessageType.video
                      ? const _VideoThumb()
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: 240,
                              maxHeight: 280,
                            ),
                            child: CachedNetworkImage(
                              imageUrl: message.mediaUrl!,
                              fit: BoxFit.contain,
                              memCacheWidth: 720,
                            ),
                          ),
                        ),
                )
              else if (message.text.isNotEmpty)
                _LinkText(text: message.text, links: links),
              if (links.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...links.map((link) => _LinkCard(link: link)),
              ],
              const SizedBox(height: 4),
              if (message.expiresAt != null)
                TickingBuilder(
                  builder: (_) => _MessageStatus(
                    message: message,
                    isMine: isMine,
                    isRead: isRead,
                    pending: pending,
                  ),
                )
              else
                _MessageStatus(
                  message: message,
                  isMine: isMine,
                  isRead: isRead,
                  pending: pending,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LinkText extends StatelessWidget {
  const _LinkText({required this.text, required this.links});

  final String text;
  final List<ChatLink> links;

  @override
  Widget build(BuildContext context) {
    if (links.isEmpty) {
      return Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 15),
      );
    }
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final link in links) {
      if (link.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, link.start)));
      }
      final raw = link.raw;
      spans.add(
        TextSpan(
          text: raw,
          style: const TextStyle(
            color: Color(0xFFB0BEC5),
            fontStyle: FontStyle.italic,
            decoration: TextDecoration.underline,
            decorationColor: Color(0xFF78909C),
            fontSize: 15,
          ),
          recognizer: TapGestureRecognizer()..onTap = () => ChatLinks.open(raw),
        ),
      );
      cursor = link.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    return Text.rich(
      TextSpan(
        style: const TextStyle(color: Colors.white, fontSize: 15),
        children: spans,
      ),
    );
  }
}

class _LinkCard extends StatelessWidget {
  const _LinkCard({required this.link});

  final ChatLink link;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () => ChatLinks.open(link.raw),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  link.label == 'Instagram'
                      ? Icons.camera_alt_outlined
                      : link.label == 'TikTok'
                      ? Icons.music_note_outlined
                      : Icons.link,
                  size: 16,
                  color: Colors.white54,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    link.label,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ],
            ),
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
    required this.pending,
  });

  final ChatMessage message;
  final bool isMine;
  final bool isRead;
  final bool pending;

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
            'düzenlendi',
            style: TextStyle(color: Colors.white30, fontSize: 11),
          ),
          const SizedBox(width: 6),
        ],
        Text(
          ChatFormat.messageTime(message.createdAt),
          style: const TextStyle(color: Colors.white30, fontSize: 11),
        ),
        if (isMine && !pending) ...[
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
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 240),
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
      ),
    );
  }
}

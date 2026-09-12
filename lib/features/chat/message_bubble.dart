import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/chat_format.dart';
import '../../core/ticking_builder.dart';
import '../../models/message_model.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.isRead,
    this.onLongPress,
  });

  final ChatMessage message;
  final bool isMine;
  final bool isRead;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final alignment = isMine ? Alignment.centerRight : Alignment.centerLeft;
    final color = isMine ? const Color(0xFF2A2A2A) : const Color(0xFF161616);

    return Align(
      alignment: alignment,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78,
          ),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF2C2C2C)),
          ),
          child: Column(
            crossAxisAlignment:
                isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (message.replyToText != null && message.replyToText!.isNotEmpty)
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
                      ? _VideoThumb(url: message.mediaUrl!)
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: CachedNetworkImage(
                            imageUrl: message.mediaUrl!,
                            width: 180,
                            height: 180,
                            fit: BoxFit.cover,
                          ),
                        ),
                )
              else
                Text(
                  message.text,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
              const SizedBox(height: 4),
              TickingBuilder(
                builder: (_) {
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
                          color: isRead
                              ? const Color(0xFF90CAF9)
                              : Colors.white38,
                        ),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VideoThumb extends StatefulWidget {
  const _VideoThumb({required this.url});
  final String url;

  @override
  State<_VideoThumb> createState() => _VideoThumbState();
}

class _VideoThumbState extends State<_VideoThumb> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    final player = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = player;
    player.initialize().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = _controller;
    if (player == null || !player.value.isInitialized) {
      return const SizedBox(
        width: 180,
        height: 120,
        child: Center(child: CircularProgressIndicator(color: Colors.white24)),
      );
    }
    return GestureDetector(
      onTap: () {
        player.value.isPlaying ? player.pause() : player.play();
        setState(() {});
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 180,
          height: 140,
          child: Stack(
            alignment: Alignment.center,
            children: [
              VideoPlayer(player),
              if (!player.value.isPlaying)
                const Icon(Icons.play_circle, color: Colors.white70, size: 40),
            ],
          ),
        ),
      ),
    );
  }
}

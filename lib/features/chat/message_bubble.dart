import 'dart:io';

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
    this.onMediaTap,
    this.onReplyTap,
    this.onLongPress,
    this.onTap,
    this.highlighted = false,
    this.selected = false,
    this.pending = false,
    this.downloaded = false,
    this.downloading = false,
    this.localPath,
  });

  final ChatMessage message;
  final bool isMine;
  final bool isRead;
  final String? senderLabel;
  final VoidCallback? onMediaTap;
  final VoidCallback? onReplyTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onTap;
  final bool highlighted;
  final bool selected;
  final bool pending;
  final bool downloaded;
  final bool downloading;
  final String? localPath;

  @override
  Widget build(BuildContext context) {
    final alignment = isMine ? Alignment.centerRight : Alignment.centerLeft;
    final color = selected
        ? const Color(0xFF1E2A33)
        : highlighted
        ? const Color(0xFF4A3F22)
        : isMine
        ? const Color(0xFF2A2A2A)
        : const Color(0xFF161616);
    final links = ChatLinks.extract(message.text);

    return Align(
      alignment: alignment,
      child: GestureDetector(
        onLongPress: onLongPress,
        onTap: onTap ?? (message.hasMedia || message.hasFile ? onMediaTap : null),
        child: Padding(
          padding: EdgeInsets.only(
            top: message.reactions.isEmpty ? 0 : 8,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.78,
                ),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected
                        ? const Color(0xFF90CAF9)
                        : highlighted
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
                        child: _MediaThumb(
                          message: message,
                          isMine: isMine,
                          pending: pending,
                          downloaded: downloaded,
                          downloading: downloading,
                          localPath: localPath,
                        ),
                      )
                    else if (message.hasFile)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: _FileChip(message: message),
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
              if (message.reactions.isNotEmpty)
                Positioned(
                  top: -2,
                  left: isMine ? 18 : null,
                  right: isMine ? null : 18,
                  child: _ReactionBadge(counts: message.reactionCounts),
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

class _FileChip extends StatelessWidget {
  const _FileChip({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final size = message.fileSize;
    final sizeLabel = size == null
        ? ''
        : size >= 1024 * 1024
        ? '${(size / (1024 * 1024)).toStringAsFixed(1)} MB'
        : '${(size / 1024).ceil()} KB';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.insert_drive_file_outlined, color: Colors.white70, size: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
                if (sizeLabel.isNotEmpty)
                  Text(
                    sizeLabel,
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReactionBadge extends StatelessWidget {
  const _ReactionBadge({required this.counts});

  final Map<String, int> counts;

  @override
  Widget build(BuildContext context) {
    final items = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3A3A3A)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < items.take(3).length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Text(items[i].key, style: const TextStyle(fontSize: 12, height: 1)),
            if (items[i].value > 1)
              Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Text(
                  '${items[i].value}',
                  style: const TextStyle(color: Colors.white54, fontSize: 10),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _MediaThumb extends StatelessWidget {
  const _MediaThumb({
    required this.message,
    required this.isMine,
    required this.pending,
    required this.downloaded,
    required this.downloading,
    this.localPath,
  });

  final ChatMessage message;
  final bool isMine;
  final bool pending;
  final bool downloaded;
  final bool downloading;
  final String? localPath;

  String? get _filePath {
    final cached = localPath;
    if (cached != null && cached.isNotEmpty && File(cached).existsSync()) {
      return cached;
    }
    if (message.isLocalMediaFile && File(message.mediaUrl!).existsSync()) {
      return message.mediaUrl;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final path = _filePath;
    final reveal = isMine || downloaded || path != null;
    final media = !reveal
        ? const _LockedThumb()
        : message.type == MessageType.video
        ? const _VideoThumb()
        : ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 240,
                maxHeight: 280,
              ),
              child: path != null
                  ? Image.file(File(path), fit: BoxFit.contain)
                  : message.isHttpMedia
                  ? CachedNetworkImage(
                      imageUrl: message.mediaUrl!,
                      fit: BoxFit.contain,
                      memCacheWidth: 720,
                    )
                  : const _LockedThumb(),
            ),
          );
    final showSpinner = downloading;
    final showTick = downloaded && !downloading;
    return Stack(
      children: [
        media,
        if (showSpinner || showTick)
          Positioned(
            left: isMine ? 6 : null,
            right: isMine ? null : 6,
            bottom: 6,
            child: _TransferMark(downloading: showSpinner),
          ),
      ],
    );
  }
}

class _TransferMark extends StatelessWidget {
  const _TransferMark({required this.downloading});

  final bool downloading;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: const BoxDecoration(
        color: Color(0xCC0B0B0B),
        shape: BoxShape.circle,
      ),
      child: downloading
          ? const Padding(
              padding: EdgeInsets.all(4),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF42A5F5),
              ),
            )
          : const Icon(
              Icons.download_done,
              size: 14,
              color: Color(0xFF42A5F5),
            ),
    );
  }
}

class _LockedThumb extends StatelessWidget {
  const _LockedThumb();

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
          Icon(Icons.download_outlined, color: Color(0xFF42A5F5), size: 28),
          SizedBox(height: 6),
          Text(
            'İndir',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
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

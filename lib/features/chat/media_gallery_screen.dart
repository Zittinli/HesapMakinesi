import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/message_model.dart';
import '../../services/chat_service.dart';

class MediaGalleryScreen extends StatelessWidget {
  const MediaGalleryScreen({
    super.key,
    required this.chatId,
    required this.viewerId,
    this.clearedAt,
  });

  final String chatId;
  final String viewerId;
  final DateTime? clearedAt;

  @override
  Widget build(BuildContext context) {
    final chatService = context.read<ChatService>();

    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B0B),
        foregroundColor: Colors.white70,
        elevation: 0,
        title: const Text(
          'Medya',
          style: TextStyle(fontWeight: FontWeight.w400),
        ),
      ),
      body: StreamBuilder<List<ChatMessage>>(
        stream: chatService.watchMessages(chatId),
        builder: (context, snapshot) {
          final images = (snapshot.data ?? [])
              .where((m) =>
                  m.type == MessageType.image &&
                  m.isVisibleTo(viewerId, clearedAt: clearedAt) &&
                  (m.mediaUrl ?? '').isNotEmpty)
              .toList();

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white24),
            );
          }

          if (images.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Henüz medya yok.\nFotoğraf ve video sonra eklenecek.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, height: 1.5),
                ),
              ),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: images.length,
            itemBuilder: (context, index) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: images[index].mediaUrl!,
                  fit: BoxFit.cover,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

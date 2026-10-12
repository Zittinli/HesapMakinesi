import 'package:cloud_firestore/cloud_firestore.dart';

import 'chat_pref_model.dart';
import 'message_model.dart';

class StarredMessage {
  const StarredMessage({
    required this.messageId,
    required this.chatId,
    required this.senderId,
    required this.text,
    required this.type,
    required this.createdAt,
    this.fileName,
  });

  final String messageId;
  final String chatId;
  final String senderId;
  final String text;
  final MessageType type;
  final DateTime createdAt;
  final String? fileName;

  String get preview {
    final body = text.trim();
    if (body.isNotEmpty) return body;
    if (type == MessageType.image) return 'Fotoğraf';
    if (type == MessageType.video) return 'Video';
    if (type == MessageType.file) {
      final name = (fileName ?? '').trim();
      return name.isEmpty ? 'Dosya' : name;
    }
    return 'Mesaj';
  }

  factory StarredMessage.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    return StarredMessage(
      messageId: doc.id,
      chatId: data['chatId'] as String? ?? '',
      senderId: data['senderId'] as String? ?? '',
      text: data['text'] as String? ?? '',
      type: ChatMessage.typeFrom(data['type'] as String?),
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      fileName: data['fileName'] as String?,
    );
  }
}

/// Ayarlar listesi gizli sohbetleri dışarıda bırakır.
/// Kişi ayrıntısı [onlyChatId] verildiğinde yalnız o sohbeti gösterir.
List<StarredMessage> visibleStarredMessages({
  required List<StarredMessage> stars,
  required Map<String, ChatPref> prefs,
  String? onlyChatId,
}) {
  final visible = <StarredMessage>[];
  for (final star in stars) {
    if (star.chatId.isEmpty || star.messageId.isEmpty) continue;
    if (onlyChatId != null && star.chatId != onlyChatId) continue;
    final pref = prefs[star.chatId];
    if (onlyChatId == null && pref?.hidden == true) continue;
    final cleared = pref?.clearedAt;
    if (cleared != null && !star.createdAt.isAfter(cleared)) continue;
    visible.add(star);
  }
  visible.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return visible;
}

import 'package:cloud_firestore/cloud_firestore.dart';

class ChatPref {
  const ChatPref({
    required this.chatId,
    this.pinned = false,
    this.pinnedAt,
    this.muted = false,
    this.hidden = false,
    this.clearedAt,
  });

  final String chatId;
  final bool pinned;
  final DateTime? pinnedAt;
  final bool muted;
  final bool hidden;
  final DateTime? clearedAt;

  factory ChatPref.empty(String chatId) => ChatPref(chatId: chatId);

  factory ChatPref.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    return ChatPref(
      chatId: doc.id,
      pinned: data['pinned'] as bool? ?? false,
      pinnedAt: (data['pinnedAt'] as Timestamp?)?.toDate(),
      muted: data['muted'] as bool? ?? false,
      hidden: data['hidden'] as bool? ?? false,
      clearedAt: (data['clearedAt'] as Timestamp?)?.toDate(),
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

class PendingThread {
  const PendingThread({
    required this.emailKey,
    required this.recipientEmail,
    required this.lastMessage,
    required this.lastMessageAt,
  });

  final String emailKey;
  final String recipientEmail;
  final String lastMessage;
  final DateTime? lastMessageAt;

  factory PendingThread.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    return PendingThread(
      emailKey: doc.id,
      recipientEmail: data['recipientEmail'] as String? ?? '',
      lastMessage: data['lastMessage'] as String? ?? '',
      lastMessageAt: (data['lastMessageAt'] as Timestamp?)?.toDate(),
    );
  }
}

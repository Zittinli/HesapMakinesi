import 'package:cloud_firestore/cloud_firestore.dart';

class ChatRoom {
  const ChatRoom({
    required this.id,
    required this.participants,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.lastMessageSenderId,
    this.unreadCounts = const {},
    this.typing = const {},
    this.blockedBy = const [],
  });

  final String id;
  final List<String> participants;
  final String lastMessage;
  final DateTime? lastMessageAt;
  final String lastMessageSenderId;
  final Map<String, int> unreadCounts;
  final Map<String, DateTime> typing;
  final List<String> blockedBy;

  factory ChatRoom.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final unreadRaw = data['unreadCounts'];
    final typingRaw = data['typing'];

    final unreadCounts = <String, int>{};
    if (unreadRaw is Map) {
      unreadRaw.forEach((key, value) {
        unreadCounts[key.toString()] = (value as num?)?.toInt() ?? 0;
      });
    }

    final typing = <String, DateTime>{};
    if (typingRaw is Map) {
      typingRaw.forEach((key, value) {
        if (value is Timestamp) {
          typing[key.toString()] = value.toDate();
        }
      });
    }

    return ChatRoom(
      id: doc.id,
      participants: List<String>.from(data['participants'] as List? ?? []),
      lastMessage: data['lastMessage'] as String? ?? '',
      lastMessageAt: (data['lastMessageAt'] as Timestamp?)?.toDate(),
      lastMessageSenderId: data['lastMessageSenderId'] as String? ?? '',
      unreadCounts: unreadCounts,
      typing: typing,
      blockedBy: List<String>.from(data['blockedBy'] as List? ?? []),
    );
  }

  String otherParticipantId(String currentUserId) {
    return participants.firstWhere(
      (id) => id != currentUserId,
      orElse: () => '',
    );
  }

  int unreadFor(String userId) => unreadCounts[userId] ?? 0;

  bool isBlocked() => blockedBy.isNotEmpty;

  bool isOtherTyping(String otherUserId, {Duration window = const Duration(seconds: 6)}) {
    final at = typing[otherUserId];
    if (at == null) return false;
    return DateTime.now().difference(at) <= window;
  }
}

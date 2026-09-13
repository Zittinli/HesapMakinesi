import 'package:cloud_firestore/cloud_firestore.dart';

class ChatRoom {
  const ChatRoom({
    required this.id,
    required this.participants,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.lastMessageSenderId,
    this.isGroup = false,
    this.groupName = '',
    this.createdBy = '',
    this.adminIds = const [],
    this.createdAt,
    this.unreadCounts = const {},
    this.typing = const {},
    this.blockedBy = const [],
  });

  final String id;
  final List<String> participants;
  final String lastMessage;
  final DateTime? lastMessageAt;
  final String lastMessageSenderId;
  final bool isGroup;
  final String groupName;
  final String createdBy;
  final List<String> adminIds;
  final DateTime? createdAt;
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
      isGroup: data['isGroup'] as bool? ?? false,
      groupName: data['groupName'] as String? ?? '',
      createdBy: data['createdBy'] as String? ?? '',
      adminIds: List<String>.from(data['adminIds'] as List? ?? const []),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
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

  String titleFor(String currentUserId, {String fallback = 'Sohbet'}) {
    if (isGroup && groupName.trim().isNotEmpty) return groupName.trim();
    return fallback;
  }

  int unreadFor(String userId) => unreadCounts[userId] ?? 0;

  /// Legacy groups used only [createdBy] to identify their administrator.
  List<String> get effectiveAdminIds {
    if (adminIds.isNotEmpty) return List<String>.unmodifiable(adminIds);
    if (isGroup && createdBy.isNotEmpty) return [createdBy];
    return const [];
  }

  bool isAdmin(String userId) => effectiveAdminIds.contains(userId);

  bool isBlocked() => blockedBy.isNotEmpty;

  bool isOtherTyping(
    String otherUserId, {
    Duration window = const Duration(seconds: 8),
  }) {
    final at = typing[otherUserId];
    if (at == null) return false;
    return DateTime.now().difference(at) <= window;
  }
}

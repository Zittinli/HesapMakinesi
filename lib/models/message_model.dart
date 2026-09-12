import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/search_tokens.dart';

enum MessageType { text, image, video }

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.text,
    required this.createdAt,
    required this.readBy,
    this.type = MessageType.text,
    this.mediaUrl,
    this.replyToId,
    this.replyToText,
    this.replyToSenderId,
    this.expiresAt,
    this.expireSeconds,
    this.deletedFor = const [],
    this.deletedForEveryone = false,
    this.editedAt,
  });

  final String id;
  final String senderId;
  final String text;
  final MessageType type;
  final String? mediaUrl;
  final DateTime? createdAt;
  final List<String> readBy;
  final String? replyToId;
  final String? replyToText;
  final String? replyToSenderId;
  final DateTime? expiresAt;
  final int? expireSeconds;
  final List<String> deletedFor;
  final bool deletedForEveryone;
  final DateTime? editedAt;

  bool get wasEdited => editedAt != null;
  bool get hasMedia =>
      (type == MessageType.image || type == MessageType.video) &&
      (mediaUrl ?? '').isNotEmpty;

  bool isReadBy(String userId) => readBy.contains(userId);

  bool isExpired([DateTime? now]) {
    if (expireSeconds == null || expiresAt == null) return false;
    if (expireSeconds != 10 && expireSeconds != 60) return false;
    return (now ?? DateTime.now()).isAfter(expiresAt!);
  }

  bool isVisibleTo(String userId, {DateTime? clearedAt}) {
    if (deletedForEveryone) return false;
    if (deletedFor.contains(userId)) return false;
    if (isExpired()) return false;
    if (clearedAt != null && createdAt != null && !createdAt!.isAfter(clearedAt)) {
      return false;
    }
    return true;
  }

  Duration? remainingTtl() {
    if (expireSeconds == null || expiresAt == null) return null;
    final left = expiresAt!.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  String get preview {
    if (type == MessageType.image) return text.isEmpty ? 'Fotograf' : text;
    if (type == MessageType.video) return text.isEmpty ? 'Video' : text;
    return text;
  }

  factory ChatMessage.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final typeRaw = data['type'] as String? ?? 'text';
    return ChatMessage(
      id: doc.id,
      senderId: data['senderId'] as String? ?? '',
      text: data['text'] as String? ?? '',
      type: typeRaw == 'video'
          ? MessageType.video
          : typeRaw == 'image'
              ? MessageType.image
              : MessageType.text,
      mediaUrl: data['mediaUrl'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      readBy: List<String>.from(data['readBy'] as List? ?? []),
      replyToId: data['replyToId'] as String?,
      replyToText: data['replyToText'] as String?,
      replyToSenderId: data['replyToSenderId'] as String?,
      expiresAt: (data['expiresAt'] as Timestamp?)?.toDate(),
      expireSeconds: (data['expireSeconds'] as num?)?.toInt(),
      deletedFor: List<String>.from(data['deletedFor'] as List? ?? []),
      deletedForEveryone: data['deletedForEveryone'] as bool? ?? false,
      editedAt: (data['editedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    final typeRaw = type == MessageType.video
        ? 'video'
        : type == MessageType.image
            ? 'image'
            : 'text';
    return {
      'senderId': senderId,
      'text': text,
      'type': typeRaw,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
      'readBy': readBy,
      'deletedFor': deletedFor,
      'deletedForEveryone': deletedForEveryone,
      'tokens': SearchTokens.fromText('$text $preview'),
      if (mediaUrl != null) 'mediaUrl': mediaUrl,
      if (replyToId != null) 'replyToId': replyToId,
      if (replyToText != null) 'replyToText': replyToText,
      if (replyToSenderId != null) 'replyToSenderId': replyToSenderId,
      if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt!),
      if (expireSeconds != null) 'expireSeconds': expireSeconds,
      if (editedAt != null) 'editedAt': Timestamp.fromDate(editedAt!),
    };
  }
}

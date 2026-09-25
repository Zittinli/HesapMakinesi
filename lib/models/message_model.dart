import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/search_tokens.dart';

enum MessageType { text, image, video, file }

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.text,
    required this.createdAt,
    required this.readBy,
    this.readAt = const {},
    this.type = MessageType.text,
    this.mediaUrl,
    this.fileName,
    this.fileSize,
    this.fileMime,
    this.replyToId,
    this.replyToText,
    this.replyToSenderId,
    this.expiresAt,
    this.expireSeconds,
    this.deletedFor = const [],
    this.deletedForEveryone = false,
    this.editedAt,
    this.reactions = const {},
  });

  final String id;
  final String senderId;
  final String text;
  final MessageType type;
  final String? mediaUrl;
  final String? fileName;
  final int? fileSize;
  final String? fileMime;
  final DateTime? createdAt;
  final List<String> readBy;
  final Map<String, DateTime> readAt;
  final String? replyToId;
  final String? replyToText;
  final String? replyToSenderId;
  final DateTime? expiresAt;
  final int? expireSeconds;
  final List<String> deletedFor;
  final bool deletedForEveryone;
  final DateTime? editedAt;
  final Map<String, String> reactions;

  bool get wasEdited => editedAt != null;
  bool get hasMedia =>
      (type == MessageType.image || type == MessageType.video) &&
      (mediaUrl ?? '').isNotEmpty;
  bool get hasFile =>
      type == MessageType.file && (mediaUrl ?? '').isNotEmpty;

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
    if (type == MessageType.image) return text.isEmpty ? 'Fotoğraf' : text;
    if (type == MessageType.video) return text.isEmpty ? 'Video' : text;
    if (type == MessageType.file) {
      return (fileName ?? '').trim().isNotEmpty
          ? fileName!.trim()
          : (text.isEmpty ? 'Dosya' : text);
    }
    return text;
  }

  Map<String, int> get reactionCounts {
    final counts = <String, int>{};
    for (final emoji in reactions.values) {
      if (emoji.isEmpty) continue;
      counts[emoji] = (counts[emoji] ?? 0) + 1;
    }
    return counts;
  }

  static MessageType typeFrom(String? raw) {
    switch (raw) {
      case 'video':
        return MessageType.video;
      case 'image':
        return MessageType.image;
      case 'file':
        return MessageType.file;
      default:
        return MessageType.text;
    }
  }

  static String typeRaw(MessageType type) {
    switch (type) {
      case MessageType.video:
        return 'video';
      case MessageType.image:
        return 'image';
      case MessageType.file:
        return 'file';
      case MessageType.text:
        return 'text';
    }
  }

  static Map<String, DateTime> _readAtOf(Object? raw) {
    if (raw is! Map) return const {};
    final result = <String, DateTime>{};
    raw.forEach((key, value) {
      if (value is Timestamp) {
        result[key.toString()] = value.toDate();
      }
    });
    return result;
  }

  static Map<String, String> _reactionsOf(Object? raw) {
    if (raw is! Map) return const {};
    final result = <String, String>{};
    raw.forEach((key, value) {
      final emoji = value?.toString().trim() ?? '';
      if (emoji.isEmpty || emoji.length > 8) return;
      result[key.toString()] = emoji;
    });
    return result;
  }

  factory ChatMessage.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return ChatMessage(
      id: doc.id,
      senderId: data['senderId'] as String? ?? '',
      text: data['text'] as String? ?? '',
      type: typeFrom(data['type'] as String?),
      mediaUrl: data['mediaUrl'] as String?,
      fileName: data['fileName'] as String?,
      fileSize: (data['fileSize'] as num?)?.toInt(),
      fileMime: data['fileMime'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      readBy: List<String>.from(data['readBy'] as List? ?? []),
      readAt: _readAtOf(data['readAt']),
      replyToId: data['replyToId'] as String?,
      replyToText: data['replyToText'] as String?,
      replyToSenderId: data['replyToSenderId'] as String?,
      expiresAt: (data['expiresAt'] as Timestamp?)?.toDate(),
      expireSeconds: (data['expireSeconds'] as num?)?.toInt(),
      deletedFor: List<String>.from(data['deletedFor'] as List? ?? []),
      deletedForEveryone: data['deletedForEveryone'] as bool? ?? false,
      editedAt: (data['editedAt'] as Timestamp?)?.toDate(),
      reactions: _reactionsOf(data['reactions']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'senderId': senderId,
      'text': text,
      'type': typeRaw(type),
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
      'readBy': readBy,
      if (readAt.isNotEmpty)
        'readAt': {
          for (final entry in readAt.entries)
            entry.key: Timestamp.fromDate(entry.value),
        },
      'deletedFor': deletedFor,
      'deletedForEveryone': deletedForEveryone,
      'tokens': SearchTokens.fromText('$text $preview ${fileName ?? ''}'),
      if (mediaUrl != null) 'mediaUrl': mediaUrl,
      if (fileName != null) 'fileName': fileName,
      if (fileSize != null) 'fileSize': fileSize,
      if (fileMime != null) 'fileMime': fileMime,
      if (replyToId != null) 'replyToId': replyToId,
      if (replyToText != null) 'replyToText': replyToText,
      if (replyToSenderId != null) 'replyToSenderId': replyToSenderId,
      if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt!),
      if (expireSeconds != null) 'expireSeconds': expireSeconds,
      if (editedAt != null) 'editedAt': Timestamp.fromDate(editedAt!),
      if (reactions.isNotEmpty) 'reactions': reactions,
    };
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/chat_model.dart';
import '../models/chat_pref_model.dart';
import '../models/message_model.dart';
import '../core/search_tokens.dart';
import '../models/pending_thread_model.dart';

class ChatBlockedException implements Exception {
  const ChatBlockedException([this.message = 'Bu yazisma engellenmis.']);
  final String message;

  @override
  String toString() => message;
}

class GroupEmailParseResult {
  const GroupEmailParseResult({
    required this.emails,
    required this.invalid,
    required this.duplicates,
  });

  final List<String> emails;
  final List<String> invalid;
  final List<String> duplicates;
}

class ChatService {
  ChatService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final Map<String, List<ChatRoom>> _chatCache = {};
  final Map<String, Map<String, ChatPref>> _prefCache = {};
  final Map<String, List<PendingThread>> _pendingCache = {};

  static const typingWindow = Duration(seconds: 6);
  static const messagePageSize = 40;

  List<ChatRoom> cachedUserChats(String userId) =>
      List<ChatRoom>.unmodifiable(_chatCache[userId] ?? const []);

  Map<String, ChatPref> cachedChatPrefs(String userId) =>
      Map<String, ChatPref>.unmodifiable(_prefCache[userId] ?? const {});

  List<PendingThread> cachedPendingSent(String userId) =>
      List<PendingThread>.unmodifiable(_pendingCache[userId] ?? const []);

  static String chatIdFor(String uid1, String uid2) {
    final ids = [uid1, uid2]..sort();
    return ids.join('_');
  }

  static String emailKey(String email) {
    return email.trim().toLowerCase().replaceAll('.', ',');
  }

  static GroupEmailParseResult parseGroupEmails(String input) {
    final values = input
        .split(RegExp(r'[\s,;]+'))
        .map((item) => item.trim().toLowerCase())
        .where((item) => item.isNotEmpty);
    final validEmail = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    final emails = <String>[];
    final invalid = <String>[];
    final duplicates = <String>[];
    final seen = <String>{};
    for (final value in values) {
      if (!validEmail.hasMatch(value)) {
        invalid.add(value);
      } else if (!seen.add(value)) {
        duplicates.add(value);
      } else {
        emails.add(value);
      }
    }
    return GroupEmailParseResult(
      emails: emails,
      invalid: invalid.toSet().toList(),
      duplicates: duplicates.toSet().toList(),
    );
  }

  static List<String> unreadRecipientIds(
    Iterable<String> participants,
    String senderId,
  ) {
    return participants
        .where((id) => id.isNotEmpty && id != senderId)
        .toSet()
        .toList();
  }

  static List<String> normalizeGroupMemberIds(Iterable<String> ids) {
    return ids
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
  }

  CollectionReference<Map<String, dynamic>> get _chats =>
      _firestore.collection('chats');

  CollectionReference<Map<String, dynamic>> _prefs(String userId) =>
      _firestore.collection('users').doc(userId).collection('chatPrefs');

  CollectionReference<Map<String, dynamic>> _blocked(String userId) =>
      _firestore.collection('users').doc(userId).collection('blocked');

  Future<ChatRoom?> getChat(String chatId) async {
    final snap = await _chats.doc(chatId).get();
    if (!snap.exists) return null;
    return ChatRoom.fromFirestore(snap);
  }

  static String? _clip(String? value, int max) {
    if (value == null) return null;
    if (value.length <= max) return value;
    return value.substring(0, max);
  }

  Stream<List<ChatRoom>> watchUserChats(String userId) {
    return _chats.where('participants', arrayContains: userId).snapshots().map((
      snapshot,
    ) {
      final chats = snapshot.docs.map(ChatRoom.fromFirestore).toList();
      chats.sort((a, b) {
        final at = a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });
      _chatCache[userId] = chats;
      return chats;
    });
  }

  Stream<ChatRoom?> watchChat(String chatId) {
    return _chats.doc(chatId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return ChatRoom.fromFirestore(doc);
    });
  }

  Stream<List<ChatMessage>> watchMessages(
    String chatId, {
    int limit = messagePageSize,
  }) {
    return _chats
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
          final messages = snapshot.docs
              .map(ChatMessage.fromFirestore)
              .toList();
          return messages.reversed.toList();
        });
  }

  Future<List<ChatMessage>> loadOlderMessages({
    required String chatId,
    required DateTime before,
    int limit = messagePageSize,
  }) {
    return _loadOlderFrom(
      _chats.doc(chatId).collection('messages'),
      before: before,
      limit: limit,
    );
  }

  Future<ChatMessage?> getMessage({
    required String chatId,
    required String messageId,
  }) async {
    final doc = await _chats
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .get();
    return doc.exists ? ChatMessage.fromFirestore(doc) : null;
  }

  Future<List<ChatMessage>> _loadOlderFrom(
    CollectionReference<Map<String, dynamic>> messages, {
    required DateTime before,
    required int limit,
  }) async {
    final snapshot = await messages
        .orderBy('createdAt', descending: true)
        .startAfter([Timestamp.fromDate(before)])
        .limit(limit)
        .get();
    final result = snapshot.docs.map(ChatMessage.fromFirestore).toList();
    return result.reversed.toList();
  }

  Stream<Map<String, ChatPref>> watchChatPrefs(String userId) {
    return _prefs(userId).snapshots().map((snapshot) {
      final prefs = {
        for (final doc in snapshot.docs) doc.id: ChatPref.fromFirestore(doc),
      };
      _prefCache[userId] = prefs;
      return prefs;
    });
  }

  Future<String> getOrCreateChat(
    String currentUserId,
    String otherUserId,
  ) async {
    final chatId = chatIdFor(currentUserId, otherUserId);
    final chatRef = _chats.doc(chatId);
    final snapshot = await chatRef.get();

    if (!snapshot.exists) {
      await chatRef.set({
        'participants': [currentUserId, otherUserId],
        'lastMessage': '',
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastMessageSenderId': '',
        'unreadCounts': {currentUserId: 0, otherUserId: 0},
        'typing': <String, dynamic>{},
        'blockedBy': <String>[],
      });
    } else {
      final existing = ChatRoom.fromFirestore(snapshot);
      if (existing.isBlocked()) {
        throw const ChatBlockedException();
      }
    }

    await _prefs(
      currentUserId,
    ).doc(chatId).set({'hidden': false}, SetOptions(merge: true));

    return chatId;
  }

  Future<String> createGroup({
    required String creatorId,
    required String groupName,
    required List<String> participantIds,
  }) async {
    final name = groupName.trim();
    final participants = <String>{
      creatorId,
      ...normalizeGroupMemberIds(participantIds),
    }.toList();
    if (name.isEmpty || name.length > 80) {
      throw ArgumentError('Grup adı 1-80 karakter olmalıdır.');
    }
    if (participants.length < 3) {
      throw ArgumentError('Grup için en az 3 katılımcı gerekir.');
    }
    if (participants.length > 20) {
      throw ArgumentError('Bir grupta en fazla 20 katılımcı olabilir.');
    }

    final chatRef = _chats.doc();
    await chatRef.set({
      'participants': participants,
      'isGroup': true,
      'groupName': name,
      'createdBy': creatorId,
      'adminIds': [creatorId],
      'createdAt': FieldValue.serverTimestamp(),
      'lastMessage': '',
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageSenderId': '',
      'unreadCounts': {for (final id in participants) id: 0},
      'typing': <String, dynamic>{},
      'blockedBy': <String>[],
    });
    return chatRef.id;
  }

  Future<void> renameGroup({
    required String chatId,
    required String groupName,
  }) async {
    final name = groupName.trim();
    if (name.isEmpty || name.length > 80) {
      throw ArgumentError('Grup adı 1-80 karakter olmalıdır.');
    }
    await _updateGroup(chatId, (state) {
      state['groupName'] = name;
    });
  }

  Future<void> addMembers({
    required String chatId,
    required Iterable<String> memberIds,
  }) async {
    final additions = normalizeGroupMemberIds(memberIds);
    if (additions.isEmpty) return;
    await _updateGroup(chatId, (state) {
      final participants = state['participants']! as List<String>;
      final updated = {...participants, ...additions}.toList();
      if (updated.length > 20) {
        throw ArgumentError('Bir grupta en fazla 20 katılımcı olabilir.');
      }
      state['participants'] = updated;
    });
  }

  Future<void> removeMember({
    required String chatId,
    required String memberId,
  }) async {
    final target = memberId.trim();
    if (target.isEmpty) throw ArgumentError('Üye kimliği boş olamaz.');
    await _updateGroup(chatId, (state) {
      final participants = state['participants']! as List<String>;
      if (!participants.contains(target)) return;
      final updatedParticipants = participants
          .where((id) => id != target)
          .toList();
      if (updatedParticipants.length < 2) {
        throw StateError('Bir grupta en az 2 katılımcı kalmalıdır.');
      }
      final admins = (state['adminIds']! as List<String>)
          .where((id) => id != target)
          .toList();
      if (admins.isEmpty) {
        throw StateError('Grupta en az bir yönetici kalmalıdır.');
      }
      state
        ..['participants'] = updatedParticipants
        ..['adminIds'] = admins;
    });
  }

  Future<void> leaveGroup({required String chatId, required String userId}) {
    return removeMember(chatId: chatId, memberId: userId);
  }

  Future<void> setGroupAdmin({
    required String chatId,
    required String memberId,
    required bool isAdmin,
  }) async {
    final target = memberId.trim();
    if (target.isEmpty) throw ArgumentError('Üye kimliği boş olamaz.');
    await _updateGroup(chatId, (state) {
      final participants = state['participants']! as List<String>;
      if (!participants.contains(target)) {
        throw StateError('Yönetici yapılacak kullanıcı grup üyesi olmalıdır.');
      }
      final admins = <String>{...(state['adminIds']! as List<String>)};
      if (isAdmin) {
        admins.add(target);
      } else {
        admins.remove(target);
      }
      if (admins.isEmpty) {
        throw StateError('Grupta en az bir yönetici kalmalıdır.');
      }
      state['adminIds'] = admins.toList();
    });
  }

  /// Intended for the hardcoded app-admin account; Firestore rules enforce it.
  Future<void> appAdminRemoveFromGroup({
    required String chatId,
    required String userId,
  }) {
    return removeMember(chatId: chatId, memberId: userId);
  }

  /// Removes a user from every eligible group and returns the changed count.
  Future<int> appAdminRemoveFromAllGroups(String userId) async {
    final snapshots = await _chats
        .where('participants', arrayContains: userId)
        .get();
    var changed = 0;
    for (final doc in snapshots.docs) {
      if (doc.data()['isGroup'] != true) continue;
      try {
        await appAdminRemoveFromGroup(chatId: doc.id, userId: userId);
        changed += 1;
      } on StateError {
        // Groups cannot be reduced below two members or left admin-less.
      }
    }
    return changed;
  }

  Future<void> _updateGroup(
    String chatId,
    void Function(Map<String, Object?> state) mutate,
  ) {
    final ref = _chats.doc(chatId);
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final data = snapshot.data();
      if (data == null || data['isGroup'] != true) {
        throw StateError('Grup bulunamadı.');
      }

      final participants = normalizeGroupMemberIds(
        List<String>.from(data['participants'] as List? ?? const []),
      );
      final createdBy = (data['createdBy'] as String? ?? '').trim();
      final storedAdmins = normalizeGroupMemberIds(
        List<String>.from(data['adminIds'] as List? ?? const []),
      );
      final admins = storedAdmins.isNotEmpty
          ? storedAdmins
          : <String>[if (createdBy.isNotEmpty) createdBy];
      final state = <String, Object?>{
        'participants': participants,
        'adminIds': admins,
        'groupName': data['groupName'] as String? ?? '',
      };
      mutate(state);

      final updatedParticipants = state['participants']! as List<String>;
      final updatedAdmins = state['adminIds']! as List<String>;
      final unreadBefore = data['unreadCounts'] is Map
          ? Map<String, dynamic>.from(data['unreadCounts'] as Map)
          : <String, dynamic>{};
      final typingBefore = data['typing'] is Map
          ? Map<String, dynamic>.from(data['typing'] as Map)
          : <String, dynamic>{};
      final updates = <String, dynamic>{
        'participants': updatedParticipants,
        'adminIds': updatedAdmins,
        'groupName': state['groupName'],
        'unreadCounts': {
          for (final id in updatedParticipants) id: unreadBefore[id] ?? 0,
        },
        'typing': {
          for (final id in updatedParticipants)
            if (typingBefore.containsKey(id)) id: typingBefore[id],
        },
      };
      if (!data.containsKey('createdAt')) {
        updates['createdAt'] = FieldValue.serverTimestamp();
      }
      transaction.update(ref, updates);
    });
  }

  Future<void> promotePendingToChat({
    required String senderId,
    required String recipientEmail,
    required String chatId,
  }) async {
    final email = recipientEmail.trim().toLowerCase();
    if (email.isEmpty || chatId.isEmpty) return;

    final inboxRef = _pendingInbox(recipientEmail: email, senderId: senderId);
    final QuerySnapshot<Map<String, dynamic>> pendingSnap;
    try {
      pendingSnap = await inboxRef.collection('messages').get();
    } catch (_) {
      return;
    }
    if (pendingSnap.docs.isEmpty) {
      try {
        await _pendingSent(senderId).doc(emailKey(email)).delete();
      } catch (_) {}
      return;
    }

    try {
      String lastPreview = '';
      for (final doc in pendingSnap.docs) {
        final data = Map<String, dynamic>.from(doc.data());
        lastPreview = (data['text'] as String?) ?? lastPreview;
        await _chats.doc(chatId).collection('messages').doc().set(data);
        await doc.reference.delete();
      }

      if (lastPreview.isNotEmpty) {
        await _chats.doc(chatId).update({
          'lastMessage': _clip(lastPreview, 180) ?? lastPreview,
          'lastMessageAt': FieldValue.serverTimestamp(),
          'lastMessageSenderId': senderId,
        });
      }

      await inboxRef.delete();
      await _pendingSent(senderId).doc(emailKey(email)).delete();
    } catch (_) {}
  }

  Future<void> sendTextMessage({
    required String chatId,
    required String senderId,
    required String text,
    ChatMessage? replyTo,
    int? expireSeconds,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final chatSnap = await _chats.doc(chatId).get();
    final chat = chatSnap.exists ? ChatRoom.fromFirestore(chatSnap) : null;
    if (chat != null && chat.isBlocked()) {
      throw const ChatBlockedException();
    }

    final expiresAt = expireSeconds == null
        ? null
        : DateTime.now().add(Duration(seconds: expireSeconds));

    final message = ChatMessage(
      id: '',
      senderId: senderId,
      text: trimmed,
      createdAt: DateTime.now(),
      readBy: [senderId],
      replyToId: replyTo?.id,
      replyToText: _clip(replyTo?.text, 400),
      replyToSenderId: replyTo?.senderId,
      expiresAt: expiresAt,
      expireSeconds: expireSeconds,
    );

    await _sendMessage(chatId, message, preview: trimmed);
  }

  Future<void> sendMediaMessage({
    required String chatId,
    required String senderId,
    required String mediaUrl,
    required MessageType type,
    ChatMessage? replyTo,
    int? expireSeconds,
  }) async {
    final chatSnap = await _chats.doc(chatId).get();
    final chat = chatSnap.exists ? ChatRoom.fromFirestore(chatSnap) : null;
    if (chat != null && chat.isBlocked()) {
      throw const ChatBlockedException();
    }
    final expiresAt = expireSeconds == null
        ? null
        : DateTime.now().add(Duration(seconds: expireSeconds));
    final label = type == MessageType.video ? 'Video' : 'Fotograf';
    final message = ChatMessage(
      id: '',
      senderId: senderId,
      text: label,
      type: type,
      mediaUrl: mediaUrl,
      createdAt: DateTime.now(),
      readBy: [senderId],
      replyToId: replyTo?.id,
      replyToText: _clip(replyTo?.text, 400),
      replyToSenderId: replyTo?.senderId,
      expiresAt: expiresAt,
      expireSeconds: expireSeconds,
    );
    await _sendMessage(chatId, message, preview: label);
  }

  Future<List<ChatMessage>> searchMessagesInChat({
    required String chatId,
    required String query,
  }) async {
    if (chatId.isEmpty || query.trim().isEmpty) return const [];
    final words = SearchTokens.wordsOf(query);
    if (words.isEmpty) return const [];
    Query<Map<String, dynamic>> ref = _chats
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt');
    try {
      final indexed = await _chats
          .doc(chatId)
          .collection('messages')
          .where('tokens', arrayContains: words.first)
          .orderBy('createdAt')
          .limit(80)
          .get();
      return indexed.docs
          .map(ChatMessage.fromFirestore)
          .where((item) => SearchTokens.matches(item.preview, query))
          .toList();
    } catch (_) {
      final fallback = await ref.limit(250).get();
      return fallback.docs
          .map(ChatMessage.fromFirestore)
          .where((item) => SearchTokens.matches(item.preview, query))
          .toList();
    }
  }

  Future<List<({ChatRoom chat, ChatMessage message})>> searchAllChats({
    required String userId,
    required String query,
  }) async {
    if (query.trim().isEmpty) return const [];
    final chats = await _chats
        .where('participants', arrayContains: userId)
        .get();
    final results = await Future.wait(
      chats.docs.map((doc) async {
        final chat = ChatRoom.fromFirestore(doc);
        final messages = await searchMessagesInChat(
          chatId: chat.id,
          query: query,
        );
        return [for (final message in messages) (chat: chat, message: message)];
      }),
    );
    final hits = results.expand((items) => items).toList();
    hits.sort((a, b) {
      final at = a.message.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bt = b.message.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bt.compareTo(at);
    });
    return hits.take(80).toList();
  }

  Future<void> _sendMessage(
    String chatId,
    ChatMessage message, {
    required String preview,
  }) async {
    final chatRef = _chats.doc(chatId);
    final messageRef = chatRef.collection('messages').doc();
    final chatSnap = await chatRef.get();
    final participants = List<String>.from(
      chatSnap.data()?['participants'] as List? ?? const [],
    );

    final updates = <String, dynamic>{
      'lastMessage': _clip(preview, 180) ?? '',
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageSenderId': message.senderId,
    };
    for (final participantId in unreadRecipientIds(
      participants,
      message.senderId,
    )) {
      updates['unreadCounts.$participantId'] = FieldValue.increment(1);
    }
    final batch = _firestore.batch();
    batch.set(messageRef, message.toFirestore());
    batch.update(chatRef, updates);
    await batch.commit();
  }

  Future<void> markMessagesAsRead({
    required String chatId,
    required String readerId,
    required List<ChatMessage> messages,
    bool writeReceipts = true,
  }) async {
    final batch = _firestore.batch();
    var writes = 0;

    if (writeReceipts) {
      for (final message in messages) {
        if (message.senderId == readerId || message.isReadBy(readerId)) {
          continue;
        }

        final ref = _chats.doc(chatId).collection('messages').doc(message.id);
        batch.update(ref, {
          'readBy': FieldValue.arrayUnion([readerId]),
        });
        writes += 1;
      }
    }

    if (writes > 0) {
      batch.update(_chats.doc(chatId), {'unreadCounts.$readerId': 0});
      await batch.commit();
    } else {
      try {
        await _chats.doc(chatId).update({'unreadCounts.$readerId': 0});
      } catch (_) {}
    }
  }

  Future<void> setTyping({
    required String chatId,
    required String userId,
    required bool typing,
  }) async {
    await _chats.doc(chatId).update({
      'typing.$userId': typing
          ? FieldValue.serverTimestamp()
          : FieldValue.delete(),
    });
  }

  Future<void> setPinned({
    required String userId,
    required String chatId,
    required bool pinned,
  }) {
    return _prefs(userId).doc(chatId).set({
      'pinned': pinned,
      'pinnedAt': pinned ? FieldValue.serverTimestamp() : FieldValue.delete(),
    }, SetOptions(merge: true));
  }

  Future<void> setMuted({
    required String userId,
    required String chatId,
    required bool muted,
  }) {
    return _prefs(
      userId,
    ).doc(chatId).set({'muted': muted}, SetOptions(merge: true));
  }

  Future<void> setHidden({
    required String userId,
    required String chatId,
    required bool hidden,
  }) {
    return _prefs(
      userId,
    ).doc(chatId).set({'hidden': hidden}, SetOptions(merge: true));
  }

  Future<void> clearChatForMe({
    required String userId,
    required String chatId,
  }) {
    return _prefs(userId).doc(chatId).set({
      'clearedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteChatForMe({
    required String userId,
    required String chatId,
  }) {
    return _prefs(userId).doc(chatId).set({
      'hidden': true,
      'clearedAt': FieldValue.serverTimestamp(),
      'pinned': false,
      'pinnedAt': FieldValue.delete(),
    }, SetOptions(merge: true));
  }

  Future<void> blockUser({
    required String userId,
    required String otherUserId,
    required String chatId,
  }) async {
    final batch = _firestore.batch();
    batch.set(_blocked(userId).doc(otherUserId), {
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(_chats.doc(chatId), {
      'blockedBy': FieldValue.arrayUnion([userId]),
    });
    batch.set(_prefs(userId).doc(chatId), {
      'hidden': true,
    }, SetOptions(merge: true));
    await batch.commit();
  }

  Future<void> unblockUser({
    required String userId,
    required String otherUserId,
    required String chatId,
  }) async {
    final batch = _firestore.batch();
    batch.delete(_blocked(userId).doc(otherUserId));
    batch.update(_chats.doc(chatId), {
      'blockedBy': FieldValue.arrayRemove([userId]),
    });
    await batch.commit();
  }

  Future<bool> isBlockedByMe(String userId, String otherUserId) async {
    final snap = await _blocked(userId).doc(otherUserId).get();
    return snap.exists;
  }

  Future<void> editMessage({
    required String chatId,
    required String messageId,
    required String senderId,
    required String text,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final ref = _chats.doc(chatId).collection('messages').doc(messageId);
    final snap = await ref.get();
    final oldText = snap.data()?['text'] as String? ?? '';

    await ref.update({
      'text': trimmed,
      'editedAt': FieldValue.serverTimestamp(),
      'tokens': SearchTokens.fromText(trimmed),
    });

    try {
      final chatSnap = await _chats.doc(chatId).get();
      final data = chatSnap.data();
      if (data != null &&
          data['lastMessageSenderId'] == senderId &&
          data['lastMessage'] == oldText) {
        await _chats.doc(chatId).update({'lastMessage': trimmed});
      }
    } catch (_) {}
  }

  Future<void> deleteMessageForMe({
    required String chatId,
    required String messageId,
    required String userId,
  }) {
    return _chats.doc(chatId).collection('messages').doc(messageId).update({
      'deletedFor': FieldValue.arrayUnion([userId]),
    });
  }

  Future<void> deleteMessageForEveryone({
    required String chatId,
    required String messageId,
    required String senderId,
  }) async {
    final ref = _chats.doc(chatId).collection('messages').doc(messageId);
    try {
      await ref.update({'deletedForEveryone': true, 'text': ''});
    } catch (_) {
      await ref.delete();
    }
  }

  Future<void> purgeExpiredMessages({
    required String chatId,
    required List<ChatMessage> messages,
  }) async {
    final expired = messages.where((m) => m.isExpired()).toList();
    if (expired.isEmpty) return;

    final batch = _firestore.batch();
    for (final message in expired) {
      batch.delete(_chats.doc(chatId).collection('messages').doc(message.id));
    }
    await batch.commit();
  }

  CollectionReference<Map<String, dynamic>> _pendingSent(String senderId) =>
      _firestore.collection('users').doc(senderId).collection('pendingSent');

  DocumentReference<Map<String, dynamic>> _pendingInbox({
    required String recipientEmail,
    required String senderId,
  }) {
    return _firestore
        .collection('pendingByEmail')
        .doc(emailKey(recipientEmail))
        .collection('inbox')
        .doc(senderId);
  }

  Stream<List<PendingThread>> watchPendingSent(String senderId) {
    return _pendingSent(senderId).snapshots().map((snapshot) {
      final threads = snapshot.docs.map(PendingThread.fromFirestore).toList();
      threads.sort((a, b) {
        final at = a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });
      _pendingCache[senderId] = threads;
      return threads;
    });
  }

  Stream<List<ChatMessage>> watchPendingMessages({
    required String senderId,
    required String recipientEmail,
    int limit = messagePageSize,
  }) {
    return _pendingInbox(recipientEmail: recipientEmail, senderId: senderId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
          final messages = snapshot.docs
              .map(ChatMessage.fromFirestore)
              .toList();
          return messages.reversed.toList();
        });
  }

  Future<List<ChatMessage>> loadOlderPendingMessages({
    required String senderId,
    required String recipientEmail,
    required DateTime before,
    int limit = messagePageSize,
  }) {
    return _loadOlderFrom(
      _pendingInbox(
        recipientEmail: recipientEmail,
        senderId: senderId,
      ).collection('messages'),
      before: before,
      limit: limit,
    );
  }

  Future<void> openPendingThread({
    required String senderId,
    required String recipientEmail,
  }) async {
    final email = recipientEmail.trim().toLowerCase();
    final sentRef = _pendingSent(senderId).doc(emailKey(email));
    final inboxRef = _pendingInbox(recipientEmail: email, senderId: senderId);
    final payload = {
      'recipientEmail': email,
      'senderId': senderId,
      'lastMessage': '',
      'lastMessageAt': FieldValue.serverTimestamp(),
    };
    await sentRef.set(payload, SetOptions(merge: true));
    await inboxRef.set(payload, SetOptions(merge: true));
  }

  Future<void> sendPendingText({
    required String senderId,
    required String recipientEmail,
    required String text,
    ChatMessage? replyTo,
    int? expireSeconds,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final email = recipientEmail.trim().toLowerCase();
    final expiresAt = expireSeconds == null
        ? null
        : DateTime.now().add(Duration(seconds: expireSeconds));
    final message = ChatMessage(
      id: '',
      senderId: senderId,
      text: trimmed,
      createdAt: DateTime.now(),
      readBy: [senderId],
      replyToId: replyTo?.id,
      replyToText: _clip(replyTo?.text, 400),
      replyToSenderId: replyTo?.senderId,
      expiresAt: expiresAt,
      expireSeconds: expireSeconds,
    );

    final inboxRef = _pendingInbox(recipientEmail: email, senderId: senderId);
    final sentRef = _pendingSent(senderId).doc(emailKey(email));
    final messageRef = inboxRef.collection('messages').doc();
    final preview = _clip(trimmed, 180) ?? '';
    final meta = {
      'recipientEmail': email,
      'senderId': senderId,
      'lastMessage': preview,
      'lastMessageAt': FieldValue.serverTimestamp(),
    };

    final batch = _firestore.batch();
    batch.set(messageRef, message.toFirestore());
    batch.set(inboxRef, meta, SetOptions(merge: true));
    batch.set(sentRef, meta, SetOptions(merge: true));
    await batch.commit();
  }

  Future<void> sendPendingMedia({
    required String senderId,
    required String recipientEmail,
    required String mediaUrl,
    required MessageType type,
    ChatMessage? replyTo,
    int? expireSeconds,
  }) async {
    final email = recipientEmail.trim().toLowerCase();
    final expiresAt = expireSeconds == null
        ? null
        : DateTime.now().add(Duration(seconds: expireSeconds));
    final label = type == MessageType.video ? 'Video' : 'Fotograf';
    final message = ChatMessage(
      id: '',
      senderId: senderId,
      text: label,
      type: type,
      mediaUrl: mediaUrl,
      createdAt: DateTime.now(),
      readBy: [senderId],
      replyToId: replyTo?.id,
      replyToText: _clip(replyTo?.text, 400),
      replyToSenderId: replyTo?.senderId,
      expiresAt: expiresAt,
      expireSeconds: expireSeconds,
    );
    final inboxRef = _pendingInbox(recipientEmail: email, senderId: senderId);
    final sentRef = _pendingSent(senderId).doc(emailKey(email));
    final messageRef = inboxRef.collection('messages').doc();
    final meta = {
      'recipientEmail': email,
      'senderId': senderId,
      'lastMessage': label,
      'lastMessageAt': FieldValue.serverTimestamp(),
    };
    final batch = _firestore.batch();
    batch.set(messageRef, message.toFirestore());
    batch.set(inboxRef, meta, SetOptions(merge: true));
    batch.set(sentRef, meta, SetOptions(merge: true));
    await batch.commit();
  }

  Future<void> claimPendingInbox({
    required String recipientId,
    required String recipientEmail,
  }) async {
    final email = recipientEmail.trim().toLowerCase();
    if (email.isEmpty) return;

    final inbox = await _firestore
        .collection('pendingByEmail')
        .doc(emailKey(email))
        .collection('inbox')
        .where('recipientEmail', isEqualTo: email)
        .get();

    for (final thread in inbox.docs) {
      final senderId = thread.id;
      if (senderId.isEmpty || senderId == recipientId) {
        continue;
      }

      String chatId;
      try {
        chatId = await getOrCreateChat(recipientId, senderId);
      } on ChatBlockedException {
        continue;
      }

      final data = thread.data();
      final lastPreview = (data['lastMessage'] as String?) ?? '';
      final messageCount =
          (await thread.reference.collection('messages').get()).size;
      if (lastPreview.isNotEmpty) {
        await _chats.doc(chatId).update({
          'lastMessage': _clip(lastPreview, 180) ?? lastPreview,
          'lastMessageAt':
              data['lastMessageAt'] ?? FieldValue.serverTimestamp(),
          'lastMessageSenderId': senderId,
          'unreadCounts.$recipientId': FieldValue.increment(messageCount),
        });
      }
    }
  }

  Stream<List<ChatMessage>> watchConversationMessages({
    required String myId,
    required String myEmail,
    String chatId = '',
    String otherId = '',
    String otherEmail = '',
  }) {
    if (chatId.isNotEmpty) {
      return watchMessages(chatId);
    }
    if (otherEmail.trim().isEmpty) {
      return Stream.value(const []);
    }
    return watchPendingMessages(senderId: myId, recipientEmail: otherEmail);
  }

  Future<List<ChatMessage>> loadOlderConversationMessages({
    required String myId,
    required String chatId,
    required String otherEmail,
    required DateTime before,
  }) {
    if (chatId.isNotEmpty) {
      return loadOlderMessages(chatId: chatId, before: before);
    }
    if (otherEmail.trim().isEmpty) return Future.value(const []);
    return loadOlderPendingMessages(
      senderId: myId,
      recipientEmail: otherEmail,
      before: before,
    );
  }

  Future<void> deleteAccountData(String userId) async {
    final chats = await _chats
        .where('participants', arrayContains: userId)
        .get();
    for (final chat in chats.docs) {
      final sent = await chat.reference
          .collection('messages')
          .where('senderId', isEqualTo: userId)
          .get();
      await _commitDeletes(sent.docs.map((doc) => doc.reference));
    }

    final userRef = _firestore.collection('users').doc(userId);
    for (final name in ['chatPrefs', 'blocked', 'pendingSent']) {
      final docs = await userRef.collection(name).get();
      await _commitDeletes(docs.docs.map((doc) => doc.reference));
    }

    try {
      await userRef.delete();
    } catch (_) {}
  }

  Future<void> _commitDeletes(
    Iterable<DocumentReference<Map<String, dynamic>>> refs,
  ) async {
    final list = refs.toList();
    for (var i = 0; i < list.length; i += 400) {
      final batch = _firestore.batch();
      final end = i + 400 > list.length ? list.length : i + 400;
      for (final ref in list.sublist(i, end)) {
        batch.delete(ref);
      }
      await batch.commit();
    }
  }
}

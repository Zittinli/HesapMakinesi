import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/chat_model.dart';
import '../models/chat_pref_model.dart';
import '../models/message_model.dart';
import '../models/pending_thread_model.dart';

class ChatBlockedException implements Exception {
  const ChatBlockedException([this.message = 'Bu yazisma engellenmis.']);
  final String message;

  @override
  String toString() => message;
}

class ChatService {
  ChatService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const typingWindow = Duration(seconds: 6);

  static String chatIdFor(String uid1, String uid2) {
    final ids = [uid1, uid2]..sort();
    return ids.join('_');
  }

  static String emailKey(String email) {
    return email.trim().toLowerCase().replaceAll('.', ',');
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
    return _chats
        .where('participants', arrayContains: userId)
        .snapshots()
        .map((snapshot) {
          final chats =
              snapshot.docs.map(ChatRoom.fromFirestore).toList();
          chats.sort((a, b) {
            final at = a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bt = b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bt.compareTo(at);
          });
          return chats;
        });
  }

  Stream<ChatRoom?> watchChat(String chatId) {
    return _chats.doc(chatId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return ChatRoom.fromFirestore(doc);
    });
  }

  Stream<List<ChatMessage>> watchMessages(String chatId) {
    return _chats
        .doc(chatId)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map(ChatMessage.fromFirestore).toList());
  }

  Stream<Map<String, ChatPref>> watchChatPrefs(String userId) {
    return _prefs(userId).snapshots().map((snapshot) {
      return {
        for (final doc in snapshot.docs) doc.id: ChatPref.fromFirestore(doc),
      };
    });
  }

  Future<String> getOrCreateChat(String currentUserId, String otherUserId) async {
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

    await _prefs(currentUserId).doc(chatId).set({
      'hidden': false,
    }, SetOptions(merge: true));

    return chatId;
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
      type: MessageType.text,
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

  Future<void> sendImageMessage({
    required String chatId,
    required String senderId,
    required String mediaUrl,
  }) async {
    final chatSnap = await _chats.doc(chatId).get();
    final chat = chatSnap.exists ? ChatRoom.fromFirestore(chatSnap) : null;
    if (chat != null && chat.isBlocked()) {
      throw const ChatBlockedException();
    }

    final message = ChatMessage(
      id: '',
      senderId: senderId,
      text: 'Fotoğraf',
      type: MessageType.image,
      mediaUrl: mediaUrl,
      createdAt: DateTime.now(),
      readBy: [senderId],
    );

    await _sendMessage(chatId, message, preview: 'Fotoğraf');
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
    final otherId = participants.firstWhere(
      (id) => id != message.senderId,
      orElse: () => '',
    );

    await messageRef.set(message.toFirestore());

    final updates = <String, dynamic>{
      'lastMessage': _clip(preview, 180) ?? '',
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageSenderId': message.senderId,
    };
    if (otherId.isNotEmpty) {
      updates['unreadCounts.$otherId'] = FieldValue.increment(1);
    }
    try {
      await chatRef.update(updates);
    } catch (_) {
      // Mesaj yazildi; onizleme guncellenmese de kaybolmasin.
    }
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
      batch.update(_chats.doc(chatId), {
        'unreadCounts.$readerId': 0,
      });
      await batch.commit();
    } else {
      try {
        await _chats.doc(chatId).update({
          'unreadCounts.$readerId': 0,
        });
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
    return _prefs(userId).doc(chatId).set({
      'muted': muted,
    }, SetOptions(merge: true));
  }

  Future<void> setHidden({
    required String userId,
    required String chatId,
    required bool hidden,
  }) {
    return _prefs(userId).doc(chatId).set({
      'hidden': hidden,
    }, SetOptions(merge: true));
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
      await ref.update({
        'deletedForEveryone': true,
        'text': '',
        'mediaUrl': null,
      });
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
      final threads =
          snapshot.docs.map(PendingThread.fromFirestore).toList();
      threads.sort((a, b) {
        final at = a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });
      return threads;
    });
  }

  Stream<List<ChatMessage>> watchPendingMessages({
    required String senderId,
    required String recipientEmail,
  }) {
    return _pendingInbox(recipientEmail: recipientEmail, senderId: senderId)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map(ChatMessage.fromFirestore).toList());
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
      type: MessageType.text,
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
          'lastMessageAt': data['lastMessageAt'] ?? FieldValue.serverTimestamp(),
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

  Future<void> deleteAccountData(String userId) async {
    final chats = await _chats.where('participants', arrayContains: userId).get();
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

  Future<void> _commitDeletes(Iterable<DocumentReference<Map<String, dynamic>>> refs) async {
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

import 'package:flutter_test/flutter_test.dart';
import 'package:hesap_makinesi/core/chat_format.dart';
import 'package:hesap_makinesi/models/chat_model.dart';
import 'package:hesap_makinesi/models/message_model.dart';
import 'package:hesap_makinesi/services/chat_service.dart';

void main() {
  group('ChatFormat', () {
    test('e-postadan bas harf uretir', () {
      expect(ChatFormat.initials('ahmet@mail.com'), 'AH');
      expect(ChatFormat.initials('a@mail.com'), 'A');
      expect(ChatFormat.initials(''), '?');
    });

    test('liste saati bugun ve dun ayirir', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 14, 5);
      expect(ChatFormat.listTime(today), '14:05');

      final yesterday = today.subtract(const Duration(days: 1));
      expect(ChatFormat.listTime(yesterday), 'Dün');
    });

    test('gun etiketi', () {
      expect(ChatFormat.dayLabel(DateTime.now()), 'Bugün');
      expect(
        ChatFormat.dayLabel(DateTime.now().subtract(const Duration(days: 1))),
        'Dün',
      );
    });
  });

  group('ChatMessage', () {
    test('suresi dolan mesaji gizler', () {
      final message = ChatMessage(
        id: '1',
        senderId: 'a',
        text: 'gizli',
        type: MessageType.text,
        createdAt: DateTime.now().subtract(const Duration(seconds: 20)),
        readBy: const ['a'],
        expiresAt: DateTime.now().subtract(const Duration(seconds: 5)),
        expireSeconds: 10,
      );

      expect(message.isExpired(), isTrue);
      expect(message.isVisibleTo('b'), isFalse);
    });

    test('temizlenen sohbet eski mesaji gizler', () {
      final created = DateTime.now().subtract(const Duration(minutes: 5));
      final message = ChatMessage(
        id: '2',
        senderId: 'a',
        text: 'eski',
        type: MessageType.text,
        createdAt: created,
        readBy: const ['a'],
      );

      expect(
        message.isVisibleTo(
          'b',
          clearedAt: created.add(const Duration(minutes: 1)),
        ),
        isFalse,
      );
      expect(message.isVisibleTo('b'), isTrue);
    });

    test('sure yokken mesaj hemen gizlenmez', () {
      final message = ChatMessage(
        id: 'ttl-off',
        senderId: 'a',
        text: 'kalici',
        type: MessageType.text,
        createdAt: DateTime.now(),
        readBy: const ['a'],
      );

      expect(message.isExpired(), isFalse);
      expect(message.isVisibleTo('b'), isTrue);
      expect(message.toFirestore().containsKey('expireSeconds'), isFalse);
    });

    test('benden silinen mesaj sadece o kullaniciya gizlenir', () {
      final message = ChatMessage(
        id: '3',
        senderId: 'a',
        text: 'sil',
        type: MessageType.text,
        createdAt: DateTime.now(),
        readBy: const ['a'],
        deletedFor: const ['b'],
      );

      expect(message.isVisibleTo('b'), isFalse);
      expect(message.isVisibleTo('a'), isTrue);
    });
  });

  group('ChatRoom', () {
    test('okunmamis sayisi ve engel', () {
      const chat = ChatRoom(
        id: 'u1_u2',
        participants: ['u1', 'u2'],
        lastMessage: 'merhaba',
        lastMessageAt: null,
        lastMessageSenderId: 'u2',
        unreadCounts: {'u1': 3, 'u2': 0},
        blockedBy: ['u1'],
      );

      expect(chat.unreadFor('u1'), 3);
      expect(chat.unreadFor('u2'), 0);
      expect(chat.otherParticipantId('u1'), 'u2');
      expect(chat.isBlocked(), isTrue);
    });

    test('yaziyor penceresi 6 saniyeden sonra kapanir', () {
      final chat = ChatRoom(
        id: 'u1_u2',
        participants: const ['u1', 'u2'],
        lastMessage: '',
        lastMessageAt: null,
        lastMessageSenderId: '',
        typing: {
          'u2': DateTime.now().subtract(const Duration(seconds: 8)),
        },
      );

      expect(chat.isOtherTyping('u2'), isFalse);
    });
  });

  test('chatId sirali ve kararli', () {
    expect(ChatService.chatIdFor('b', 'a'), ChatService.chatIdFor('a', 'b'));
    expect(ChatService.chatIdFor('a', 'b'), 'a_b');
  });
}

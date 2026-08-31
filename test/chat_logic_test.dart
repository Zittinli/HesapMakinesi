import 'package:flutter_test/flutter_test.dart';
import 'package:hesap_makinesi/core/admin_config.dart';
import 'package:hesap_makinesi/core/chat_format.dart';
import 'package:hesap_makinesi/models/chat_model.dart';
import 'package:hesap_makinesi/models/message_model.dart';
import 'package:hesap_makinesi/models/moderation_model.dart';
import 'package:hesap_makinesi/models/report_model.dart';
import 'package:hesap_makinesi/models/user_model.dart';
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

    test('son gorulme ve son aktif etiketi', () {
      final now = DateTime(2026, 8, 30, 20, 0);
      expect(
        ChatFormat.lastSeenLabel(now, now: now, isOnline: true),
        'Aktif',
      );
      expect(
        ChatFormat.lastSeenLabel(
          DateTime(2026, 8, 30, 19, 59),
          now: now,
        ),
        'Son aktif: az once',
      );
      expect(
        ChatFormat.lastSeenLabel(
          DateTime(2026, 8, 30, 14, 5),
          now: now,
        ),
        'Son gorulme: 14:05',
      );
      expect(
        ChatFormat.lastSeenLabel(
          DateTime(2026, 8, 29, 14, 5),
          now: now,
        ),
        'Son gorulme: Dün 14:05',
      );
    });
  });

  group('ChatMessage', () {
    test('suresi dolan mesaji gizler', () {
      final message = ChatMessage(
        id: '1',
        senderId: 'a',
        text: 'gizli',
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

    test('yaziyor penceresi 8 saniyeden sonra kapanir', () {
      final chat = ChatRoom(
        id: 'u1_u2',
        participants: const ['u1', 'u2'],
        lastMessage: '',
        lastMessageAt: null,
        lastMessageSenderId: '',
        typing: {
          'u2': DateTime.now().subtract(const Duration(seconds: 9)),
        },
      );

      expect(chat.isOtherTyping('u2'), isFalse);
    });
  });

  test('chatId sirali ve kararli', () {
    expect(ChatService.chatIdFor('b', 'a'), ChatService.chatIdFor('a', 'b'));
    expect(ChatService.chatIdFor('a', 'b'), 'a_b');
  });

  group('Moderation', () {
    test('yonetici e-postasini tanir', () {
      expect(AdminConfig.isAdminEmail('zttnlnkc@gmail.com'), isTrue);
      expect(AdminConfig.isAdminEmail('ZTTNLNKC@GMAIL.COM'), isTrue);
      expect(AdminConfig.isAdminEmail('zittuni1912@gmail.com'), isFalse);
      expect(AdminConfig.isAdminEmail('baskasi@gmail.com'), isFalse);
    });

    test('kalici ban ve timeout kisitlar', () {
      expect(const ModerationStatus(bannedPermanently: true).isRestricted(), isTrue);
      expect(
        ModerationStatus(
          timeoutUntil: DateTime.now().add(const Duration(hours: 1)),
        ).isRestricted(),
        isTrue,
      );
      expect(
        ModerationStatus(
          timeoutUntil: DateTime.now().subtract(const Duration(minutes: 1)),
        ).isRestricted(),
        isFalse,
      );
    });

    test('kalici ban timeouta ustun gelir', () {
      final banned = const ModerationStatus(bannedPermanently: true);
      final timeout = ModerationStatus(
        timeoutUntil: DateTime.now().add(const Duration(days: 1)),
      );
      expect(ModerationStatus.stricter(timeout, banned).bannedPermanently, isTrue);
    });
  });

  group('email OTP kayit kapisi', () {
    test('eski kullanici kod ekranina dusmez', () {
      final user = AppUser(
        id: 'u1',
        email: 'eski@example.com',
        displayName: 'Eski',
        isOnline: false,
        lastSeen: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
      );
      expect(user.needsEmailOtp, isFalse);
    });

    test('yeni kullanici kod dogrulamadan gecemez', () {
      final user = AppUser(
        id: 'u2',
        email: 'yeni@example.com',
        displayName: 'Yeni',
        isOnline: false,
        lastSeen: DateTime(2026, 8, 31),
        createdAt: DateTime(2026, 8, 31),
        acceptedTermsAt: DateTime(2026, 8, 31),
      );
      expect(user.needsEmailOtp, isTrue);
    });

    test('kod onaylaninca kapı acilir', () {
      final user = AppUser(
        id: 'u3',
        email: 'yeni@example.com',
        displayName: 'Yeni',
        isOnline: false,
        lastSeen: DateTime(2026, 8, 31),
        createdAt: DateTime(2026, 8, 31),
        acceptedTermsAt: DateTime(2026, 8, 31),
        emailOtpVerified: true,
      );
      expect(user.needsEmailOtp, isFalse);
    });
  });

  test('bildirimler sikayet edilen kullaniciya gore gruplanir', () {
    MessageReport report({
      required String id,
      required String email,
      required String status,
    }) {
      return MessageReport(
        id: id,
        reporterId: 'r1',
        reporterEmail: 'a@x.com',
        reportedUserId: 'u-$email',
        reportedEmail: email,
        chatId: 'c1',
        messageId: id,
        messageText: 'msg $id',
        reason: ReportReason.abuse,
        status: status,
        createdAt: DateTime(2026, 8, 31),
      );
    }

    final groups = groupReportsByUser([
      report(id: '1', email: 'bad@x.com', status: 'pending'),
      report(id: '2', email: 'bad@x.com', status: 'reviewed'),
      report(id: '3', email: 'other@x.com', status: 'pending'),
    ]);
    expect(groups, hasLength(2));
    final bad = groups.firstWhere((item) => item.email == 'bad@x.com');
    expect(bad.reports, hasLength(2));
    expect(bad.pendingCount, 1);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:hesap_makinesi/core/admin_config.dart';
import 'package:hesap_makinesi/core/emoji_catalog.dart';
import 'package:hesap_makinesi/core/chat_format.dart';
import 'package:hesap_makinesi/core/staff_perms.dart';
import 'package:hesap_makinesi/features/settings/admin_search_field.dart';
import 'package:hesap_makinesi/models/chat_model.dart';
import 'package:hesap_makinesi/models/message_model.dart';
import 'package:hesap_makinesi/models/moderation_model.dart';
import 'package:hesap_makinesi/models/report_model.dart';
import 'package:hesap_makinesi/models/user_model.dart';
import 'package:hesap_makinesi/services/chat_service.dart';
import 'package:hesap_makinesi/services/outgoing_queue_service.dart';

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
      expect(ChatFormat.listTime(yesterday), 'Dün 14:05');
    });

    test('gun etiketi', () {
      expect(ChatFormat.dayLabel(DateTime.now()), 'Bugün');
      expect(
        ChatFormat.dayLabel(DateTime.now().subtract(const Duration(days: 1))),
        'Dün',
      );
    });

    test('mesaj saati Turkiye UTC+3 basar', () {
      expect(
        ChatFormat.messageTime(DateTime.utc(2026, 10, 7, 21, 31, 25)),
        '00:31',
      );
      expect(
        ChatFormat.eventDateTime(DateTime.utc(2026, 10, 7, 21, 31, 25)),
        '08.10.2026 00:31',
      );
    });

    test('son görülme ve son aktif etiketi', () {
      final now = DateTime(2026, 8, 30, 20, 0);
      expect(ChatFormat.lastSeenLabel(now, now: now, isOnline: true), 'Aktif');
      expect(
        ChatFormat.lastSeenLabel(
          DateTime(2026, 8, 30, 18, 0),
          now: now,
          isOnline: true,
        ),
        'Son görülme: 18:00',
      );
      expect(
        ChatFormat.lastSeenLabel(DateTime(2026, 8, 30, 19, 59), now: now),
        'Son aktif: az önce',
      );
      expect(
        ChatFormat.lastSeenLabel(DateTime(2026, 8, 30, 14, 5), now: now),
        'Son görülme: 14:05',
      );
      expect(
        ChatFormat.lastSeenLabel(DateTime(2026, 8, 29, 14, 5), now: now),
        'Son görülme: Dün 14:05',
      );
    });
  });

  group('ChatMessage', () {
    test('suresi dolan mesajı gizler', () {
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

    test('suresi dolunca expiredDeleted ile gizlenir', () {
      const message = ChatMessage(
        id: '3',
        senderId: 'a',
        text: 'gizli',
        createdAt: null,
        readBy: ['a'],
        expireSeconds: 10,
        expiredDeleted: true,
      );

      expect(message.isVisibleTo('b'), isFalse);
      expect(message.toFirestore()['expiredDeleted'], isTrue);
    });

    test('temizlenen sohbet eski mesajı gizler', () {
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
        text: 'kalıcı',
        createdAt: DateTime.now(),
        readBy: const ['a'],
      );

      expect(message.isExpired(), isFalse);
      expect(message.isVisibleTo('b'), isTrue);
      expect(message.toFirestore().containsKey('expireSeconds'), isFalse);
    });

    test('dosya onizlemesi dosya adini kullanir', () {
      const message = ChatMessage(
        id: 'f1',
        senderId: 'a',
        text: 'Dosya',
        createdAt: null,
        readBy: ['a'],
        type: MessageType.file,
        mediaUrl: 'https://example.com/x',
        fileName: 'sozlesme.pdf',
        fileSize: 1200,
      );
      expect(message.preview, 'sozlesme.pdf');
      expect(message.hasFile, isTrue);
      expect(message.hasMedia, isFalse);
      expect(message.isHttpMedia, isTrue);
      expect(message.isStoragePath, isFalse);
    });

    test('medya yolu http degil depolama yoludur', () {
      const stored = ChatMessage(
        id: 'm1',
        senderId: 'a',
        text: 'Fotoğraf',
        createdAt: null,
        readBy: ['a'],
        type: MessageType.image,
        mediaUrl: 'chat_media/c1/123.jpg',
      );
      const pending = ChatMessage(
        id: 'm2',
        senderId: 'a',
        text: 'Fotoğraf',
        createdAt: null,
        readBy: ['a'],
        type: MessageType.image,
        mediaUrl: 'pending_media/ali,gmail,com/1.jpg',
      );
      const local = ChatMessage(
        id: 'm3',
        senderId: 'a',
        text: 'Fotoğraf',
        createdAt: null,
        readBy: ['a'],
        type: MessageType.image,
        mediaUrl: '/tmp/a.jpg',
      );
      expect(stored.isStoragePath, isTrue);
      expect(stored.isHttpMedia, isFalse);
      expect(stored.isLocalMediaFile, isFalse);
      expect(pending.isStoragePath, isTrue);
      expect(local.isLocalMediaFile, isTrue);
      expect(local.isStoragePath, isFalse);
    });

    test('reaksiyon sayilarini birlestirir', () {
      const message = ChatMessage(
        id: 'r1',
        senderId: 'a',
        text: 'hi',
        createdAt: null,
        readBy: ['a'],
        reactions: {'u1': '👍', 'u2': '👍', 'u3': '❤️'},
      );
      expect(message.reactionCounts['👍'], 2);
      expect(message.reactionCounts['❤️'], 1);
    });

    test('yerel taslak sunucuya yazilana kadar pending kalir', () {
      const local = ChatMessage(
        id: 'local-1',
        senderId: 'a',
        text: 'merhaba',
        createdAt: null,
        readBy: ['a'],
        pendingWrite: true,
        clientKey: 'local-1',
      );
      expect(local.pendingWrite, isTrue);
      final acked = local.copyWith(pendingWrite: false);
      expect(acked.pendingWrite, isFalse);
      expect(acked.clientKey, 'local-1');
    });

    test('benden silinen mesaj sadece o kullanıcıya gizlenir', () {
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
    test('okunmamis sayısi ve engel', () {
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

    test('yazıyor penceresi 8 saniyeden sonra kapanır', () {
      final chat = ChatRoom(
        id: 'u1_u2',
        participants: const ['u1', 'u2'],
        lastMessage: '',
        lastMessageAt: null,
        lastMessageSenderId: '',
        typing: {'u2': DateTime.now().subtract(const Duration(seconds: 9))},
      );

      expect(chat.isOtherTyping('u2'), isFalse);
    });

    test('grup başlığını ve katılımcıları korur', () {
      const chat = ChatRoom(
        id: 'group-id',
        participants: ['u1', 'u2', 'u3'],
        lastMessage: '',
        lastMessageAt: null,
        lastMessageSenderId: '',
        isGroup: true,
        groupName: 'Proje Ekibi',
        createdBy: 'u1',
      );

      expect(chat.titleFor('u2'), 'Proje Ekibi');
      expect(chat.otherParticipantId('u2'), 'u1');
      expect(chat.participants, hasLength(3));
    });

    test('eski grupta kurucuyu yönetici kabul eder', () {
      const legacy = ChatRoom(
        id: 'legacy-group',
        participants: ['u1', 'u2', 'u3'],
        lastMessage: '',
        lastMessageAt: null,
        lastMessageSenderId: '',
        isGroup: true,
        groupName: 'Eski Grup',
        createdBy: 'u1',
      );

      expect(legacy.effectiveAdminIds, ['u1']);
      expect(legacy.isAdmin('u1'), isTrue);
      expect(legacy.isAdmin('u2'), isFalse);
    });

    test('yeni yönetici listesi kurucu geri dönüşünün önüne geçer', () {
      const chat = ChatRoom(
        id: 'managed-group',
        participants: ['u1', 'u2', 'u3'],
        lastMessage: '',
        lastMessageAt: null,
        lastMessageSenderId: '',
        isGroup: true,
        groupName: 'Yönetilen Grup',
        createdBy: 'u1',
        adminIds: ['u2'],
      );

      expect(chat.effectiveAdminIds, ['u2']);
      expect(chat.isAdmin('u1'), isFalse);
      expect(chat.isAdmin('u2'), isTrue);
    });
  });

  test('chatId sirali ve kararli', () {
    expect(ChatService.chatIdFor('b', 'a'), ChatService.chatIdFor('a', 'b'));
    expect(ChatService.chatIdFor('a', 'b'), 'a_b');
  });

  group('grup oluşturma yardımcıları', () {
    test('üye kimliklerini temizler ve tekilleştirir', () {
      expect(ChatService.normalizeGroupMemberIds([' u1 ', '', 'u2', 'u1']), [
        'u1',
        'u2',
      ]);
    });

    test('e-postaları normalize eder ve sorunları ayrı bildirir', () {
      final parsed = ChatService.parseGroupEmails(
        'ALI@EXAMPLE.COM,\nveli@example.com ali@example.com;bozuk',
      );

      expect(parsed.emails, ['ali@example.com', 'veli@example.com']);
      expect(parsed.duplicates, ['ali@example.com']);
      expect(parsed.invalid, ['bozuk']);
    });

    test('okunmamış sayacı gönderen dışındaki herkese gider', () {
      final recipients = ChatService.unreadRecipientIds([
        'u1',
        'u2',
        'u3',
        'u2',
      ], 'u1');

      expect(recipients.toSet(), {'u2', 'u3'});
    });

    test('son yönetici ayrılınca kalan ilk üyeyi yönetici yapar', () {
      expect(
        ChatService.adminsAfterMemberLeave(
          adminIds: ['u1'],
          remainingParticipants: ['u2', 'u3'],
          leavingId: 'u1',
        ),
        ['u2'],
      );
    });

    test('yönetici olmayan ayrılınca diğer yöneticiler kalır', () {
      expect(
        ChatService.adminsAfterMemberLeave(
          adminIds: ['u1', 'u2'],
          remainingParticipants: ['u1', 'u2'],
          leavingId: 'u3',
        ),
        ['u1', 'u2'],
      );
    });
  });

  group('Moderation', () {
    test('yönetici e-postasini tanir', () {
      expect(AdminConfig.isAdminEmail('zttnlnkc@gmail.com'), isTrue);
      expect(AdminConfig.isAdminEmail('ZTTNLNKC@GMAIL.COM'), isTrue);
      expect(AdminConfig.isAdminEmail('zittuni1912@gmail.com'), isFalse);
      expect(AdminConfig.isAdminEmail('baskasi@gmail.com'), isFalse);
      expect(AdminConfig.isFounder(email: 'zttnlnkc@gmail.com'), isTrue);
    });

    test('ceza raporu ust yetkisi bildirim gormeyi de acar', () {
      final granted = StaffPerm.toggle(const [], StaffPerm.punishReports);
      expect(granted.contains(StaffPerm.viewReports), isTrue);
      expect(granted.contains(StaffPerm.punishReports), isTrue);
      final withoutView = StaffPerm.toggle(granted, StaffPerm.viewReports);
      expect(withoutView.contains(StaffPerm.punishReports), isFalse);
    });

    test('grup timeout yetkisi gruplari gormeyi acar', () {
      final granted = StaffPerm.toggle(const [], StaffPerm.timeoutGroup);
      expect(granted.contains(StaffPerm.viewGroups), isTrue);
      final withoutGroups = StaffPerm.toggle(granted, StaffPerm.viewGroups);
      expect(withoutGroups.contains(StaffPerm.timeoutGroup), isFalse);
    });

    test('admin arama ad ve e-postayi yakalar', () {
      expect(adminSearchMatches('', ['Ada', 'a@x.com']), isTrue);
      expect(adminSearchMatches('ada', ['Ada', 'a@x.com']), isTrue);
      expect(adminSearchMatches('x.com', ['Ada', 'a@x.com']), isTrue);
      expect(adminSearchMatches('zzz', ['Ada', 'a@x.com']), isFalse);
    });

    test('gizli profil fotografi ve grup timeout', () {
      const hidden = AppUser(
        id: 'u',
        email: 'a@x.com',
        displayName: 'Ada',
        isOnline: false,
        lastSeen: null,
        createdAt: null,
        photoUrl: 'https://example.com/a.jpg',
        photoHidden: true,
      );
      expect(hidden.visiblePhotoUrl, isNull);
      const shown = AppUser(
        id: 'u',
        email: 'a@x.com',
        displayName: 'Ada',
        isOnline: false,
        lastSeen: null,
        createdAt: null,
        photoUrl: 'https://example.com/a.jpg',
      );
      expect(shown.visiblePhotoUrl, 'https://example.com/a.jpg');
      expect(ReportReason.profilePhoto.label, 'Uygunsuz profil fotoğrafı');
      expect(
        ChatRoom(
          id: 'g',
          participants: const ['a', 'b', 'c'],
          lastMessage: '',
          lastMessageAt: null,
          lastMessageSenderId: '',
          isGroup: true,
          groupName: 'Grup',
          groupTimeoutUntil: DateTime.now().add(const Duration(hours: 1)),
        ).isGroupTimedOut(),
        isTrue,
      );
    });

    test('kalıcı ban ve timeout kişitlar', () {
      expect(
        const ModerationStatus(bannedPermanently: true).isRestricted(),
        isTrue,
      );
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

    test('kalıcı ban timeouta ustun gelir', () {
      final banned = const ModerationStatus(bannedPermanently: true);
      final timeout = ModerationStatus(
        timeoutUntil: DateTime.now().add(const Duration(days: 1)),
      );
      expect(
        ModerationStatus.stricter(timeout, banned).bannedPermanently,
        isTrue,
      );
    });

    test('grup raporu kullanıcı altında gruplanır ve grup bilgisini korur', () {
      const report = MessageReport(
        id: 'r1',
        reporterId: 'u1',
        reporterEmail: 'bildiren@example.com',
        reportedUserId: 'u2',
        reportedEmail: 'bildirilen@example.com',
        chatId: 'g1',
        messageId: 'm1',
        messageText: 'mesaj',
        reason: ReportReason.abuse,
        status: 'pending',
        isGroup: true,
        groupName: 'Arkadaşlar',
      );

      final groups = groupReportsByUser([report]);
      expect(groups, hasLength(1));
      expect(groups.single.pendingCount, 1);
      expect(groups.single.reports.single.groupName, 'Arkadaşlar');
      expect(groups.single.reports.single.isGroup, isTrue);
    });
  });

  group('email OTP kayıt kapisi', () {
    test('eski kullanıcı kod ekranına dusmez', () {
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

    test('yeni kullanıcı kod doğrulamadan gecemez', () {
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

  test('bildirimler sikayet edilen kullanıcıya gore gruplanir', () {
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

  group('OutgoingJob', () {
    test('json turu tiksiz taslak olarak geri gelir', () {
      final job = OutgoingJob(
        id: 'local-1',
        senderId: 'u1',
        createdAtMs: DateTime(2026, 10, 8, 3).millisecondsSinceEpoch,
        text: 'merhaba',
        type: MessageType.text,
        chatId: 'c1',
        expireSeconds: 60,
      );
      final copy = OutgoingJob.fromJson(job.toJson());
      expect(copy.id, 'local-1');
      expect(copy.chatId, 'c1');
      expect(copy.expireSeconds, 60);
      final message = copy.toMessage();
      expect(message.pendingWrite, isTrue);
      expect(message.clientKey, 'local-1');
      expect(message.text, 'merhaba');
    });

    test('medya kuyrugu sohbet bazinda ayrilir', () {
      final photo = OutgoingJob(
        id: 'local-2',
        senderId: 'u1',
        createdAtMs: 1,
        text: 'Fotoğraf',
        type: MessageType.image,
        chatId: 'c1',
        localPath: '/tmp/a.jpg',
      );
      final other = photo.copyWith(status: 'queued');
      expect(other.chatId, 'c1');
      expect(photo.isMedia, isTrue);
      expect(photo.toMessage().mediaUrl, '/tmp/a.jpg');
      expect(photo.toMessage().pendingWrite, isTrue);
    });
  });

  group('EmojiCatalog', () {
    test('hizli emoji listesini kirpar ve tekrarlar', () {
      final cleaned = EmojiCatalog.normalize([
        ' 👍 ',
        '👍',
        '',
        '😂',
        '🔥',
        '🎉',
        '💯',
        '🥰',
        '😍',
        '😘',
        '😊',
      ]);
      expect(cleaned, ['👍', '😂', '🔥', '🎉', '💯', '🥰', '😍', '😘']);
      expect(cleaned, hasLength(EmojiCatalog.maxQuick));
    });
  });
}

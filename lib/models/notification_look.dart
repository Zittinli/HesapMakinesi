class NotificationCopy {
  const NotificationCopy({required this.title, required this.body});

  final String title;
  final String body;

  static NotificationCopy? of({
    required NotificationLook look,
    required String sender,
    required String preview,
  }) {
    final name = sender.trim().isEmpty ? 'Kayit' : sender.trim();
    final text = preview.trim().isEmpty ? 'Yeni kayit' : preview.trim();

    switch (look) {
      case NotificationLook.off:
        return null;
      case NotificationLook.cover:
        return const NotificationCopy(
          title: 'HesapMakinesi',
          body: 'Son islem kaydedildi',
        );
      case NotificationLook.record:
        return const NotificationCopy(
          title: 'Kayitlar',
          body: 'Yeni kayit',
        );
      case NotificationLook.sender:
        return NotificationCopy(title: name, body: 'Yeni kayit');
      case NotificationLook.preview:
        return NotificationCopy(title: name, body: text);
    }
  }
}

enum NotificationLook {
  off,
  cover,
  record,
  sender,
  preview;

  String get label {
    switch (this) {
      case NotificationLook.off:
        return 'Kapali';
      case NotificationLook.cover:
        return 'Hesap makinesi kilifi';
      case NotificationLook.record:
        return 'Kayit';
      case NotificationLook.sender:
        return 'Gonderen';
      case NotificationLook.preview:
        return 'Gonderen ve metin';
    }
  }

  String get hint {
    switch (this) {
      case NotificationLook.off:
        return 'Bildirim gosterilmez.';
      case NotificationLook.cover:
        return 'HesapMakinesi / Son islem kaydedildi';
      case NotificationLook.record:
        return 'Kayitlar / Yeni kayit';
      case NotificationLook.sender:
        return 'Kisinin adi / Yeni kayit';
      case NotificationLook.preview:
        return 'Kisinin adi / mesaj metni';
    }
  }
}

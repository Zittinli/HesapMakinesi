class NotificationCopy {
  const NotificationCopy({required this.title, required this.body});

  final String title;
  final String body;

  static NotificationCopy? of({
    required NotificationLook look,
    required String sender,
    required String preview,
  }) {
    final name = sender.trim().isEmpty ? 'Kayıt' : sender.trim();
    final text = preview.trim().isEmpty ? 'Yeni kayıt' : preview.trim();

    switch (look) {
      case NotificationLook.off:
        return null;
      case NotificationLook.cover:
        return const NotificationCopy(
          title: 'HesapMakinesi',
          body: 'Son işlem kaydedildi',
        );
      case NotificationLook.record:
        return const NotificationCopy(
          title: 'Kayıtlar',
          body: 'Yeni kayıt',
        );
      case NotificationLook.sender:
        return NotificationCopy(title: name, body: 'Yeni kayıt');
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
        return 'Kapalı';
      case NotificationLook.cover:
        return 'Gizli';
      case NotificationLook.record:
        return 'Kayıt';
      case NotificationLook.sender:
        return 'Gönderen';
      case NotificationLook.preview:
        return 'Gönderen ve metin';
    }
  }

  String get hint {
    switch (this) {
      case NotificationLook.off:
        return 'Bildirim yok.';
      case NotificationLook.cover:
        return 'Hesap makinesi gibi görünür.';
      case NotificationLook.record:
        return 'Yalnızca kayıt.';
      case NotificationLook.sender:
        return 'Gönderen adı.';
      case NotificationLook.preview:
        return 'Ad ve mesaj.';
    }
  }
}

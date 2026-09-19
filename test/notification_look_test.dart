import 'package:flutter_test/flutter_test.dart';
import 'package:hesap_makinesi/models/notification_look.dart';

void main() {
  test('kilif bildirimi mesaj metnini gizler', () {
    final copy = NotificationCopy.of(
      look: NotificationLook.cover,
      sender: 'Ahmet',
      preview: 'gizli metin',
    );

    expect(copy, isNotNull);
    expect(copy!.title, 'HesapMakinesi');
    expect(copy.body, 'Son işlem kaydedildi');
  });

  test('tam görünüm gönderen ve metni gösterir', () {
    final copy = NotificationCopy.of(
      look: NotificationLook.preview,
      sender: 'Ahmet',
      preview: 'Yarın görüşürüz',
    );

    expect(copy!.title, 'Ahmet');
    expect(copy.body, 'Yarın görüşürüz');
  });

  test('kapalı görünüm bildirim uretmez', () {
    expect(
      NotificationCopy.of(
        look: NotificationLook.off,
        sender: 'Ahmet',
        preview: 'x',
      ),
      isNull,
    );
  });
}

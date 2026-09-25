# Firestore grup yönetimi kural incelemesi

## Kapsam ve varsayımlar

- Veritabanı: `(default)`, Standard edition, native mode, `eur3`.
- Yeni gruplar 3-20 kişiyle kurulur; ayrılma/çıkarma sonrasında en az 2 kişi
  ve en az 1 yönetici kalır.
- `adminIds` aktif üyelerin alt kümesidir. Eski gruplarda `createdBy`, ilk
  yönetici olarak kabul edilip ilk yönetim işleminde yeni şemaya taşınır.
- `createdBy` tarihsel kurucudur ve değiştirilemez; kurucu gruptan ayrılabilir.
- Uygulama yöneticisi yalnızca doğrulanmış sabit yönetici e-postasıyla tanınır.

## Kötüye kullanım denemeleri

- Oturumsuz veya üye olmayan sohbet/mesaj okuma ve yazma: reddedilir.
- Normal üyenin kendisini yönetici yapması, grup adını değiştirmesi, üye
  eklemesi veya başka üyeyi çıkarması: reddedilir.
- Grup yöneticisinin `createdBy`, `createdAt`, `isGroup` ya da mesaj alanlarını
  grup yönetimi güncellemesine karıştırması: alan farkı kontrolüyle reddedilir.
- Son yöneticiyi kaldırma, yöneticiler listesine üye olmayan UID ekleme,
  yinelenen/boş/uzun UID ve 20 kişiyi aşma: doğrulayıcıyla reddedilir.
- Normal üyenin ayrılma isteğine başka alan veya başka üye değişikliği
  eklemesi: tam liste farkı ve tek UID kontrolüyle reddedilir.
- Eski grubun ilk yönetim işleminde `createdAt` için sunucu zamanı dışında
  değer yazması: reddedilir.
- Sahte raporda üye olunmayan sohbeti veya sohbet üyesi olmayan hedefi
  kullanma: reddedilir.
- Rapor oluşturulduktan sonra hedef, kanıt, grup veya kimlik alanlarını
  değiştirme: admin güncelleme alan listesiyle reddedilir.
- `readBy` / `deletedFor` içine katılımcı olmayan UID ekleme, büyük metin,
  medya URL'si veya bilinmeyen alanla şema kirletme: reddedilir.

## Sonuç

Grup yönetimi için yetki kaynağı yalnızca mevcut `resource.data` ve doğrulanmış
auth tokenıdır; istemcinin yazmak istediği yeni roller yetki kaynağı yapılmaz.
Kurallar güçlü bir prototiptir ancak geniş kullanıcı dağıtımından önce
Firestore Emulator ile çok kullanıcılı entegrasyon testleri de çalıştırılmalıdır.

`firebase deploy --only firestore:rules --dry-run` kural dosyasını başarıyla
derledi; rapor şeması değişikliğinden sonra doğrulama yeniden çalıştırılacaktır.

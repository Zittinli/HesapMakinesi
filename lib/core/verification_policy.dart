import 'package:firebase_auth/firebase_auth.dart';

/// E-posta dogrulama zorunlulugunun ne zamandan sonraki hesaplar icin
/// gecerli oldugunu belirler. Bu tarihten once kayit olan kullanicilar,
/// dogrulama akisi eklenmeden once girdikleri icin muaf tutulur.
class VerificationPolicy {
  static final DateTime enforcedAfter = DateTime.utc(2026, 8, 31, 16, 15);

  static bool isExempt(User user) {
    final createdAt = user.metadata.creationTime;
    if (createdAt == null) return false;
    return createdAt.toUtc().isBefore(enforcedAfter);
  }
}

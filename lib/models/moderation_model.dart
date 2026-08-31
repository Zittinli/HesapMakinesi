import 'package:cloud_firestore/cloud_firestore.dart';

class ModerationStatus {
  const ModerationStatus({
    this.bannedPermanently = false,
    this.timeoutUntil,
    this.reason = '',
    this.email = '',
  });

  final bool bannedPermanently;
  final DateTime? timeoutUntil;
  final String reason;
  final String email;

  static const empty = ModerationStatus();

  bool isRestricted([DateTime? now]) {
    if (bannedPermanently) return true;
    final until = timeoutUntil;
    if (until == null) return false;
    return until.isAfter(now ?? DateTime.now());
  }

  String get label {
    if (bannedPermanently) return 'Hesap kalici olarak kapatildi.';
    if (isRestricted()) {
      final until = timeoutUntil!;
      final stamp =
          '${until.day.toString().padLeft(2, '0')}.${until.month.toString().padLeft(2, '0')} '
          '${until.hour.toString().padLeft(2, '0')}:${until.minute.toString().padLeft(2, '0')}';
      return 'Hesap $stamp tarihine kadar askida.';
    }
    return '';
  }

  factory ModerationStatus.fromMap(Map<String, dynamic>? data) {
    if (data == null) return empty;
    return ModerationStatus(
      bannedPermanently: data['bannedPermanently'] as bool? ?? false,
      timeoutUntil: (data['timeoutUntil'] as Timestamp?)?.toDate(),
      reason: data['reason'] as String? ?? '',
      email: data['email'] as String? ?? '',
    );
  }

  static ModerationStatus stricter(ModerationStatus a, ModerationStatus b) {
    if (a.bannedPermanently) return a;
    if (b.bannedPermanently) return b;
    final aUntil = a.timeoutUntil;
    final bUntil = b.timeoutUntil;
    if (aUntil != null && bUntil != null) {
      return aUntil.isAfter(bUntil) ? a : b;
    }
    if (aUntil != null) return a;
    return b;
  }
}

class AccountRestrictedException implements Exception {
  const AccountRestrictedException([this.message = 'Hesabiniz askida.']);
  final String message;

  @override
  String toString() => message;
}

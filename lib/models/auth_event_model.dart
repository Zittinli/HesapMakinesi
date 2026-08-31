import 'package:cloud_firestore/cloud_firestore.dart';

class AuthEvent {
  const AuthEvent({
    required this.id,
    required this.type,
    required this.email,
    required this.uid,
    required this.success,
    this.errorCode = '',
    this.createdAt,
  });

  final String id;
  final String type;
  final String email;
  final String uid;
  final bool success;
  final String errorCode;
  final DateTime? createdAt;

  String get label {
    switch (type) {
      case 'sign_in':
        return 'Giris basarili';
      case 'sign_in_failed':
        return 'Giris basarisiz';
      case 'sign_up':
        return 'Yeni kayit';
      case 'password_reset':
        return 'Sifre sifirlama';
      case 'otp_sent':
        return 'Onay kodu gonderildi';
      case 'otp_failed':
        return 'Onay kodu hatali';
      case 'otp_verified':
        return 'Onay kodu dogrulandi';
      case 'sign_out':
        return 'Cikis';
      default:
        return type;
    }
  }

  factory AuthEvent.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    return AuthEvent(
      id: doc.id,
      type: data['type'] as String? ?? '',
      email: data['email'] as String? ?? '',
      uid: data['uid'] as String? ?? '',
      success: data['success'] as bool? ?? false,
      errorCode: data['errorCode'] as String? ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.isOnline,
    required this.lastSeen,
    required this.createdAt,
    this.shareLastSeen = true,
    this.acceptedTermsAt,
    this.emailOtpVerified = false,
  });

  final String id;
  final String email;
  final String displayName;
  final bool isOnline;
  final DateTime? lastSeen;
  final DateTime? createdAt;
  final bool shareLastSeen;
  final DateTime? acceptedTermsAt;
  final bool emailOtpVerified;

  bool get needsEmailOtp {
    if (emailOtpVerified) return false;
    return acceptedTermsAt != null;
  }

  factory AppUser.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return AppUser(
      id: doc.id,
      email: data['email'] as String? ?? '',
      displayName: data['displayName'] as String? ?? '',
      isOnline: data['isOnline'] as bool? ?? false,
      lastSeen: (data['lastSeen'] as Timestamp?)?.toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      shareLastSeen: data['shareLastSeen'] as bool? ?? true,
      acceptedTermsAt: (data['acceptedTermsAt'] as Timestamp?)?.toDate(),
      emailOtpVerified: data['emailOtpVerified'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'email': email,
      'displayName': displayName,
      'isOnline': isOnline,
      'lastSeen': lastSeen != null ? Timestamp.fromDate(lastSeen!) : null,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
      'shareLastSeen': shareLastSeen,
      if (acceptedTermsAt != null)
        'acceptedTermsAt': Timestamp.fromDate(acceptedTermsAt!),
      'emailOtpVerified': emailOtpVerified,
    };
  }
}

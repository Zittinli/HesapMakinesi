import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/chat_format.dart';
import '../core/emoji_catalog.dart';

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
    this.displayNameChangedAt,
    this.quickEmojis,
    this.photoUrl = '',
    this.photoHidden = false,
    this.staffPerms = const [],
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
  final DateTime? displayNameChangedAt;
  final List<String>? quickEmojis;
  final String photoUrl;
  final bool photoHidden;
  final List<String> staffPerms;

  String get visibleName =>
      displayName.trim().isNotEmpty ? displayName.trim() : email;

  String? get visiblePhotoUrl {
    if (photoHidden) return null;
    if (photoUrl.startsWith('http')) return photoUrl;
    return null;
  }

  bool get hasStaffAccess => staffPerms.isNotEmpty;

  bool isEffectivelyOnline([DateTime? now]) => ChatFormat.isFreshOnline(
        isOnline: isOnline,
        lastSeen: lastSeen,
        now: now,
      );

  Duration? get displayNameCooldown {
    final last = displayNameChangedAt;
    if (last == null) return null;
    final left = last.add(const Duration(hours: 1)).difference(DateTime.now());
    return left.isNegative ? null : left;
  }

  bool get needsEmailOtp {
    if (emailOtpVerified) return false;
    return acceptedTermsAt != null;
  }

  static List<String>? _readQuickEmojis(Object? raw) {
    if (raw is! List) return null;
    final cleaned = EmojiCatalog.normalize(raw.whereType<String>());
    if (cleaned.isEmpty) return null;
    return cleaned;
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
      displayNameChangedAt:
          (data['displayNameChangedAt'] as Timestamp?)?.toDate(),
      quickEmojis: _readQuickEmojis(data['quickEmojis']),
      photoUrl: data['photoUrl'] as String? ?? '',
      photoHidden: data['photoHidden'] as bool? ?? false,
      staffPerms: List<String>.from(data['staffPerms'] as List? ?? const []),
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
      if (displayNameChangedAt != null)
        'displayNameChangedAt': Timestamp.fromDate(displayNameChangedAt!),
    };
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../core/admin_config.dart';
import '../core/verification_policy.dart';
import '../models/user_model.dart';
import 'auth_log_service.dart';
import 'chat_service.dart';
import 'email_check_service.dart';

class AuthService extends ChangeNotifier {
  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    AuthLogService? authLog,
    EmailCheckService? emailCheck,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _authLog = authLog ?? AuthLogService(),
        _emailCheck = emailCheck ?? EmailCheckService();

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final AuthLogService _authLog;
  final EmailCheckService _emailCheck;

  User? get currentUser => _auth.currentUser;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  Future<void> signIn(String email, String password) async {
    final normalized = email.trim().toLowerCase();
    try {
      await _auth.signInWithEmailAndPassword(
        email: normalized,
        password: password,
      );
      await _ensureUserDocument();
      await _markLogin();
      await _authLog.log(type: 'sign_in', email: normalized);
      if (!requiresEmailVerification) {
        await _claimPending();
      }
      notifyListeners();
    } on FirebaseAuthException catch (error) {
      await _authLog.log(
        type: 'sign_in_failed',
        email: normalized,
        success: false,
        errorCode: error.code,
      );
      rethrow;
    } catch (error) {
      await _authLog.log(
        type: 'sign_in_failed',
        email: normalized,
        success: false,
        errorCode: 'unknown',
      );
      rethrow;
    }
  }

  Future<void> sendPasswordReset(String email) async {
    final normalized = email.trim().toLowerCase();
    try {
      await _auth.sendPasswordResetEmail(email: normalized);
      await _authLog.log(type: 'password_reset', email: normalized);
    } on FirebaseAuthException catch (error) {
      await _authLog.log(
        type: 'password_reset',
        email: normalized,
        success: false,
        errorCode: error.code,
      );
      if (error.code == 'user-not-found' ||
          error.code == 'invalid-email') {
        return;
      }
      rethrow;
    }
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String displayName,
    required bool acceptedTerms,
  }) async {
    if (!acceptedTerms) {
      throw FirebaseAuthException(
        code: 'terms-required',
        message: 'Aydinlatma metnini onaylaman gerekir.',
      );
    }

    await _emailCheck.ensureDeliverable(email);

    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = credential.user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'user-null',
        message: 'Kullanici olusturulamadi.',
      );
    }

    final appUser = AppUser(
      id: user.uid,
      email: email.trim().toLowerCase(),
      displayName: displayName.trim(),
      isOnline: false,
      lastSeen: DateTime.now(),
      createdAt: DateTime.now(),
      acceptedTermsAt: DateTime.now(),
      emailOtpVerified: false,
    );

    await _firestore.collection('users').doc(user.uid).set(appUser.toFirestore());
    await _authLog.log(type: 'sign_up', email: email.trim().toLowerCase());
    try {
      await user.sendEmailVerification();
    } catch (error) {
      debugPrint('Dogrulama e-postasi gonderilemedi: $error');
    }
    notifyListeners();
  }

  bool get requiresEmailVerification {
    final user = _auth.currentUser;
    if (user == null) return false;
    if (AdminConfig.isAdminEmail(user.email)) return false;
    if (VerificationPolicy.isExempt(user)) return false;
    return !user.emailVerified;
  }

  Future<void> sendVerificationEmail() async {
    final user = _auth.currentUser;
    if (user == null || user.emailVerified) return;
    await user.sendEmailVerification();
    await _authLog.log(
      type: 'otp_sent',
      email: user.email ?? '',
    );
  }

  /// Firebase'den taze kullanici bilgisini ceker ve dogrulanmissa
  /// bekleyen mesajlari devralir.
  Future<bool> refreshEmailVerified() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    await user.reload();
    final refreshed = _auth.currentUser;
    final verified = refreshed?.emailVerified == true;
    if (verified) {
      await _authLog.log(
        type: 'otp_verified',
        email: refreshed?.email ?? '',
      );
      await _claimPending();
      notifyListeners();
    }
    return verified;
  }

  Future<void> deleteAccount(String password) async {
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null || email == null || email.isEmpty) {
      throw FirebaseAuthException(
        code: 'no-user',
        message: 'Oturum bulunamadi.',
      );
    }

    final credential = EmailAuthProvider.credential(
      email: email,
      password: password,
    );
    await user.reauthenticateWithCredential(credential);
    await ChatService(firestore: _firestore).deleteAccountData(user.uid);
    await user.delete();
    notifyListeners();
  }

  Future<void> signOut() async {
    final uid = _auth.currentUser?.uid;
    final email = _auth.currentUser?.email ?? '';
    if (uid != null) {
      await _firestore.collection('users').doc(uid).update({
        'isOnline': false,
        'lastSeen': FieldValue.serverTimestamp(),
      });
    }
    if (email.isNotEmpty) {
      await _authLog.log(type: 'sign_out', email: email);
    }
    await _auth.signOut();
    notifyListeners();
  }

  Future<void> _ensureUserDocument() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final doc = _firestore.collection('users').doc(user.uid);
    final snapshot = await doc.get();
    if (!snapshot.exists) {
      await doc.set(
        AppUser(
          id: user.uid,
          email: user.email ?? '',
          displayName: user.email?.split('@').first ?? 'Kullanici',
          isOnline: true,
          lastSeen: DateTime.now(),
          createdAt: DateTime.now(),
        ).toFirestore(),
      );
    }
  }

  Future<void> _markLogin() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await _firestore.collection('users').doc(user.uid).update({
        'lastLoginAt': FieldValue.serverTimestamp(),
        'isOnline': true,
        'lastSeen': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Future<AppUser?> findUserByEmail(String email) async {
    final normalized = email.trim().toLowerCase();
    final query = await _firestore
        .collection('users')
        .where('email', isEqualTo: normalized)
        .limit(1)
        .get();

    if (query.docs.isEmpty) return null;
    return AppUser.fromFirestore(query.docs.first);
  }

  Future<void> _claimPending() async {
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null || email == null || email.isEmpty) return;
    try {
      await ChatService(firestore: _firestore).claimPendingInbox(
        recipientId: user.uid,
        recipientEmail: email,
      );
    } catch (_) {}
  }

  Future<void> updateDisplayName(String name) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-user',
        message: 'Oturum bulunamadi.',
      );
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 80) {
      throw FirebaseAuthException(
        code: 'invalid-name',
        message: 'Gorunen ad 1-80 karakter olmali.',
      );
    }
    final doc = _firestore.collection('users').doc(user.uid);
    final snapshot = await doc.get();
    if (!snapshot.exists) {
      throw FirebaseAuthException(
        code: 'no-profile',
        message: 'Profil bulunamadi.',
      );
    }
    final profile = AppUser.fromFirestore(snapshot);
    final cooldown = profile.displayNameCooldown;
    if (cooldown != null) {
      final minutes = cooldown.inMinutes + 1;
      throw FirebaseAuthException(
        code: 'name-cooldown',
        message: 'Gorunen ad $minutes dakika sonra degistirilebilir.',
      );
    }
    await doc.update({
      'displayName': trimmed,
      'displayNameChangedAt': FieldValue.serverTimestamp(),
    });
    notifyListeners();
  }

  Stream<List<AppUser>> watchAllUsers() {
    return _firestore.collection('users').snapshots().map((snapshot) {
      final users = snapshot.docs.map(AppUser.fromFirestore).toList();
      users.sort((a, b) {
        final at = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });
      return users;
    });
  }

  Stream<AppUser?> watchUser(String userId) {
    return _firestore.collection('users').doc(userId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return AppUser.fromFirestore(doc);
    });
  }
}

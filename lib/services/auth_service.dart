import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/user_model.dart';
import 'auth_log_service.dart';
import 'chat_service.dart';

class AuthService extends ChangeNotifier {
  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    AuthLogService? authLog,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _authLog = authLog ?? AuthLogService();

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final AuthLogService _authLog;

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
      if (!await requiresEmailOtp()) {
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
    notifyListeners();
  }

  Future<bool> requiresEmailOtp() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    final snap = await _firestore.collection('users').doc(user.uid).get();
    if (!snap.exists) return false;
    return AppUser.fromFirestore(snap).needsEmailOtp;
  }

  Future<void> completeEmailVerification() async {
    await _claimPending();
    notifyListeners();
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

  Stream<AppUser?> watchUser(String userId) {
    return _firestore.collection('users').doc(userId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return AppUser.fromFirestore(doc);
    });
  }
}

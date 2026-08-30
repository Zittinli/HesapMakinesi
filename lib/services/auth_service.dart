import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/user_model.dart';
import 'chat_service.dart';

class AuthService extends ChangeNotifier {
  AuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  User? get currentUser => _auth.currentUser;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  Future<void> signIn(String email, String password) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
    await _ensureUserDocument();
    await _claimPending();
    notifyListeners();
  }

  Future<void> signUp(String email, String password, String displayName) async {
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
      isOnline: true,
      lastSeen: DateTime.now(),
      createdAt: DateTime.now(),
    );

    await _firestore.collection('users').doc(user.uid).set(appUser.toFirestore());
    await _claimPending();
    notifyListeners();
  }

  Future<void> signOut() async {
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      await _firestore.collection('users').doc(uid).update({
        'isOnline': false,
        'lastSeen': FieldValue.serverTimestamp(),
      });
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

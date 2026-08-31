import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/auth_event_model.dart';

class AuthLogService {
  AuthLogService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _events =>
      _firestore.collection('authEvents');

  Future<void> log({
    required String type,
    required String email,
    bool success = true,
    String errorCode = '',
  }) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.length < 3) return;
    try {
      await _events.add({
        'type': type,
        'email': normalized.length > 120
            ? normalized.substring(0, 120)
            : normalized,
        'uid': _auth.currentUser?.uid ?? '',
        'success': success,
        'errorCode': errorCode.length > 80
            ? errorCode.substring(0, 80)
            : errorCode,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Stream<List<AuthEvent>> watchEvents() {
    return _events
        .orderBy('createdAt', descending: true)
        .limit(300)
        .snapshots()
        .map((snap) => snap.docs.map(AuthEvent.fromFirestore).toList());
  }
}

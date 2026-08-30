import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';

import 'settings_service.dart';

class PresenceService with WidgetsBindingObserver {
  PresenceService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    SettingsService? settings,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _settings = settings;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final SettingsService? _settings;

  bool _wantOnline = false;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _settings?.addListener(_syncPresence);
    _wantOnline = true;
    _syncPresence();
  }

  void stop() {
    WidgetsBinding.instance.removeObserver(this);
    _settings?.removeListener(_syncPresence);
    _wantOnline = false;
    _syncPresence();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _wantOnline = true;
        _syncPresence();
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _wantOnline = false;
        _syncPresence();
    }
  }

  void _syncPresence() {
    _writePresence(_wantOnline);
  }

  Future<void> _writePresence(bool wantOnline) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final share = _settings?.lastSeenEnabled ?? true;
    await _firestore.collection('users').doc(uid).update({
      'isOnline': wantOnline && share,
      'lastSeen': FieldValue.serverTimestamp(),
      'shareLastSeen': share,
    });
  }
}

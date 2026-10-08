import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';

import '../core/chat_format.dart';
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
  Timer? _heartbeat;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _settings?.addListener(_syncPresence);
    _wantOnline = true;
    _syncPresence();
    _armHeartbeat();
  }

  void stop() {
    WidgetsBinding.instance.removeObserver(this);
    _settings?.removeListener(_syncPresence);
    _heartbeat?.cancel();
    _heartbeat = null;
    _wantOnline = false;
    _syncPresence();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _wantOnline = true;
        _syncPresence();
        _armHeartbeat();
      case AppLifecycleState.inactive:
        if (_wantOnline) _writePresence(true);
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _heartbeat?.cancel();
        _heartbeat = null;
        _wantOnline = false;
        _syncPresence();
    }
  }

  void _armHeartbeat() {
    _heartbeat?.cancel();
    if (!_wantOnline) return;
    _heartbeat = Timer.periodic(ChatFormat.presenceHeartbeat, (_) {
      if (_wantOnline) _writePresence(true);
    });
  }

  void _syncPresence() {
    _writePresence(_wantOnline);
  }

  Future<void> _writePresence(bool wantOnline) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final share = _settings?.lastSeenEnabled ?? true;
    try {
      await _firestore.collection('users').doc(uid).update({
        'isOnline': wantOnline && share,
        'lastSeen': FieldValue.serverTimestamp(),
        'shareLastSeen': share,
      });
    } on FirebaseException catch (error) {
      debugPrint('Presence yazılamadı: ${error.code}');
    }
  }
}

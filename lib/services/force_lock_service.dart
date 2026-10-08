import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'chat_service.dart';

class ForceLockService extends ChangeNotifier {
  ForceLockService({
    required AuthService authService,
    required ChatService chatService,
  })  : _authService = authService,
        _chatService = chatService;

  static const pendingKey = 'force_lock_pending';

  final AuthService _authService;
  final ChatService _chatService;
  StreamSubscription<User?>? _authSub;
  StreamSubscription<List<IncomingNudge>>? _inboxSub;
  bool _primed = false;
  bool _trip = false;
  String? _uid;

  bool get trip => _trip;

  void consumeTrip() {
    if (!_trip) return;
    _trip = false;
    notifyListeners();
  }

  void start() {
    unawaited(_restorePending());
    _authSub ??= _authService.authStateChanges().listen(_onAuth);
    _onAuth(_authService.currentUser);
  }

  Future<void> _restorePending() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(pendingKey) == true) {
      _trip = true;
      notifyListeners();
    }
  }

  Future<void> _setPending(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(pendingKey, value);
  }

  void _onAuth(User? user) {
    if (user?.uid == _uid && (_inboxSub != null || user == null)) return;
    _inboxSub?.cancel();
    _inboxSub = null;
    _primed = false;
    _uid = user?.uid;
    if (user == null) return;
    _inboxSub = _chatService.watchIncomingForceLocks(user.uid).listen(
      _onInbox,
      onError: (_) {
        _inboxSub?.cancel();
        _inboxSub = null;
      },
      cancelOnError: true,
    );
  }

  void _onInbox(List<IncomingNudge> items) {
    if (!_primed) {
      _primed = true;
      for (final item in items) {
        unawaited(_chatService.consumeIncomingForceLock(
          userId: _uid ?? '',
          lockId: item.id,
        ));
      }
      return;
    }
    for (final item in items) {
      unawaited(_chatService.consumeIncomingForceLock(
        userId: _uid ?? '',
        lockId: item.id,
      ));
      _trip = true;
      unawaited(_setPending(true));
      notifyListeners();
    }
  }

  Future<void> clearPending() => _setPending(false);

  Future<void> send({
    required String toId,
    required String chatId,
  }) async {
    final fromId = _authService.currentUser?.uid;
    if (fromId == null) {
      throw StateError('Gönderilemedi.');
    }
    await _chatService.sendForceLock(fromId: fromId, toId: toId, chatId: chatId);
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _inboxSub?.cancel();
    super.dispose();
  }
}

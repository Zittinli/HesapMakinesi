import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'chat_service.dart';
import 'nudge_haptic.dart';

class NudgeService extends ChangeNotifier {
  NudgeService({
    required AuthService authService,
    required ChatService chatService,
  }) : _authService = authService,
       _chatService = chatService;

  static const _pendingKey = 'pending_nudge_chats';
  static const _sendGap = Duration(milliseconds: 700);

  final AuthService _authService;
  final ChatService _chatService;
  final _events = StreamController<IncomingNudge>.broadcast();
  final Set<String> _pendingChatIds = {};
  StreamSubscription<User?>? _authSub;
  StreamSubscription<List<IncomingNudge>>? _inboxSub;
  DateTime? _lastSentAt;
  bool _primed = false;
  String? _uid;

  Stream<IncomingNudge> get events => _events.stream;
  bool hasPending(String chatId) => _pendingChatIds.contains(chatId);

  void start() {
    unawaited(_loadPending());
    _authSub ??= _authService.authStateChanges().listen(_onAuth);
    _onAuth(_authService.currentUser);
  }

  Future<void> _loadPending() async {
    final prefs = await SharedPreferences.getInstance();
    _pendingChatIds
      ..clear()
      ..addAll(prefs.getStringList(_pendingKey) ?? const []);
    notifyListeners();
  }

  Future<void> _savePending() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_pendingKey, _pendingChatIds.toList());
  }

  void _mark(String chatId) {
    if (chatId.isEmpty || !_pendingChatIds.add(chatId)) return;
    notifyListeners();
    unawaited(_savePending());
  }

  Future<void> clearChat(String chatId) async {
    if (chatId.isEmpty || !_pendingChatIds.remove(chatId)) return;
    notifyListeners();
    await _savePending();
  }

  void _onAuth(User? user) {
    if (user?.uid == _uid && (_inboxSub != null || user == null)) return;
    _inboxSub?.cancel();
    _inboxSub = null;
    _primed = false;
    _uid = user?.uid;
    if (user == null) {
      _pendingChatIds.clear();
      notifyListeners();
      return;
    }
    _inboxSub = _chatService.watchIncomingNudges(user.uid).listen(
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
        final created = item.createdAt;
        if (created == null ||
            DateTime.now().difference(created) < const Duration(hours: 24)) {
          _mark(item.chatId);
        }
        unawaited(_consume(item.id));
      }
      return;
    }
    for (final item in items) {
      if (!NudgeHaptic.isFresh(item.createdAt)) {
        if (item.createdAt == null ||
            DateTime.now().difference(item.createdAt!) <
                const Duration(hours: 24)) {
          _mark(item.chatId);
        }
        unawaited(_consume(item.id));
        continue;
      }
      _mark(item.chatId);
      unawaited(NudgeHaptic.play());
      if (!_events.isClosed) _events.add(item);
      unawaited(_consume(item.id));
    }
  }

  Future<void> _consume(String id) async {
    final uid = _uid;
    if (uid == null || id.isEmpty) return;
    try {
      await _chatService.consumeIncomingNudge(userId: uid, nudgeId: id);
    } catch (_) {}
  }

  Future<void> send({
    required String toId,
    required String chatId,
  }) async {
    final fromId = _authService.currentUser?.uid;
    if (fromId == null) {
      throw StateError('Dürtme gönderilemedi.');
    }
    final last = _lastSentAt;
    if (last != null && DateTime.now().difference(last) < _sendGap) {
      throw StateError('Biraz bekleyip tekrar dürt.');
    }
    await _chatService.sendNudge(fromId: fromId, toId: toId, chatId: chatId);
    _lastSentAt = DateTime.now();
    await HapticFeedback.selectionClick();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _inboxSub?.cancel();
    _events.close();
    super.dispose();
  }
}

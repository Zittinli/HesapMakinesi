import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/chat_model.dart';
import '../models/chat_pref_model.dart';
import '../models/notification_look.dart';
import 'auth_service.dart';
import 'chat_service.dart';
import 'settings_service.dart';

class NotificationService {
  NotificationService({
    required SettingsService settings,
    required ChatService chatService,
    required AuthService authService,
  })  : _settings = settings,
        _chatService = chatService,
        _authService = authService;

  final SettingsService _settings;
  final ChatService _chatService;
  final AuthService _authService;
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  final Map<String, DateTime> _seenAt = {};
  StreamSubscription<User?>? _authSub;
  StreamSubscription<List<ChatRoom>>? _chatsSub;
  StreamSubscription<Map<String, ChatPref>>? _prefsSub;
  StreamSubscription<String>? _tokenSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  Map<String, ChatPref> _prefs = {};
  bool _hubOpen = false;
  bool _ready = false;
  bool _primed = false;

  void setHubOpen(bool open) {
    _hubOpen = open;
  }

  Future<void> start() async {
    if (_ready) return;
    _ready = true;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings();
      await _plugin.initialize(
        settings: const InitializationSettings(android: android, iOS: ios),
      );
    } catch (_) {}

    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: false,
        sound: true,
      );
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
        alert: true,
        badge: false,
        sound: true,
      );
      _foregroundSub =
          FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    } catch (_) {}

    _authSub = _authService.authStateChanges().listen(_onAuth);
    final user = _authService.currentUser;
    if (user != null) {
      _listenChats(user.uid);
    }
  }

  void _onAuth(User? user) {
    _chatsSub?.cancel();
    _prefsSub?.cancel();
    _tokenSub?.cancel();
    _seenAt.clear();
    _primed = false;
    _prefs = {};
    if (user == null) {
      _plugin.cancelAll();
      return;
    }
    _listenChats(user.uid);
    unawaited(_syncPushToken(user.uid));
    _tokenSub = FirebaseMessaging.instance.onTokenRefresh.listen((_) {
      unawaited(_syncPushToken(user.uid));
    });
  }

  Future<void> _syncPushToken(String uid) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;
      final id = token.replaceAll('/', '_').replaceAll('.', '_');
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('fcmTokens')
          .doc(id)
          .set({
        'token': token,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  void _onForegroundMessage(RemoteMessage message) {
    if (_hubOpen) return;
    final title = message.notification?.title ??
        message.data['sender'] ??
        'Kayit';
    final body = message.notification?.body ??
        message.data['preview'] ??
        '';
    unawaited(
      showMessage(
        id: (message.data['chatId'] ?? title).hashCode,
        sender: title,
        preview: body,
      ),
    );
  }

  void _listenChats(String uid) {
    _prefsSub = _chatService.watchChatPrefs(uid).listen((prefs) {
      _prefs = prefs;
    });
    _chatsSub = _chatService.watchUserChats(uid).listen((chats) {
      _onChats(uid, chats);
    });
  }

  void _onChats(String uid, List<ChatRoom> chats) {
    if (!_primed) {
      for (final chat in chats) {
        _seenAt[chat.id] = chat.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      }
      _primed = true;
      return;
    }

    for (final chat in chats) {
      final at = chat.lastMessageAt;
      if (at == null) continue;
      final previous = _seenAt[chat.id];
      _seenAt[chat.id] = at;
      if (previous != null && !at.isAfter(previous)) continue;
      if (chat.lastMessageSenderId == uid || chat.lastMessageSenderId.isEmpty) {
        continue;
      }
      if (_prefs[chat.id]?.muted == true) continue;
      if (_hubOpen) continue;
      unawaited(_showForChat(chat, uid));
    }
  }

  Future<void> _showForChat(ChatRoom chat, String uid) async {
    final otherId = chat.otherParticipantId(uid);
    var sender = 'Kayit';
    if (otherId.isNotEmpty) {
      final user = await _authService.watchUser(otherId).first;
      if (user != null) {
        sender = user.displayName.isNotEmpty ? user.displayName : user.email;
      }
    }
    await showMessage(
      id: chat.id.hashCode,
      sender: sender,
      preview: chat.lastMessage,
    );
  }

  Future<void> requestPermission() async {
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (_) {}
  }

  Future<void> showMessage({
    required int id,
    required String sender,
    required String preview,
  }) async {
    final copy = NotificationCopy.of(
      look: _settings.notificationLook,
      sender: sender,
      preview: preview,
    );
    if (copy == null) return;

    await requestPermission();
    final silent = !_settings.soundEnabled && !_settings.vibrateEnabled;
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        silent ? 'hm_silent' : 'hm_alert',
        silent ? 'Hesaplamalar' : 'Kayitlar',
        channelDescription: silent ? 'Sessiz uyarilar' : 'Kayit uyarilari',
        importance: silent ? Importance.low : Importance.high,
        priority: silent ? Priority.low : Priority.high,
        playSound: _settings.soundEnabled,
        enableVibration: _settings.vibrateEnabled,
        silent: silent,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentSound: _settings.soundEnabled,
        presentBadge: false,
      ),
    );

    try {
      await _plugin.show(
        id: id,
        title: copy.title,
        body: copy.body,
        notificationDetails: details,
      );
    } catch (_) {}
  }

  Future<void> showPreview() {
    return showMessage(
      id: 991991,
      sender: 'Ahmet',
      preview: 'Yarin gorusuruz',
    );
  }

  void dispose() {
    _authSub?.cancel();
    _chatsSub?.cancel();
    _prefsSub?.cancel();
    _tokenSub?.cancel();
    _foregroundSub?.cancel();
  }
}

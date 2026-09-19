import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/chat_model.dart';
import '../models/chat_pref_model.dart';
import '../models/notification_look.dart';
import 'auth_service.dart';
import 'chat_service.dart';
import 'nudge_haptic.dart';
import 'settings_service.dart';

class NotificationService with WidgetsBindingObserver {
  NotificationService({
    required SettingsService settings,
    required ChatService chatService,
    required AuthService authService,
  }) : _settings = settings,
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
  String? _activeUid;
  DateTime? _startedAt;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;

  void setHubOpen(bool open) {
    _hubOpen = open;
  }

  Future<void> start() async {
    if (_ready) return;
    _ready = true;
    _startedAt = DateTime.now();
    WidgetsBinding.instance.addObserver(this);
    _authSub = _authService.authStateChanges().listen(_onAuth);
    _onAuth(_authService.currentUser);

    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings();
      await _plugin.initialize(
        settings: const InitializationSettings(android: android, iOS: ios),
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              'hm_alert',
              'Kayıtlar',
              description: 'Kayıt uyarıları',
              importance: Importance.high,
              playSound: true,
              enableVibration: true,
            ),
          );
    } catch (error) {
      debugPrint('HM_NOTIFY_INIT_FAILED: $error');
    }

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
      _foregroundSub = FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    } catch (_) {}
  }

  void _onAuth(User? user) {
    if (user?.uid == _activeUid && (_chatsSub != null || user == null)) return;
    _chatsSub?.cancel();
    _prefsSub?.cancel();
    _tokenSub?.cancel();
    _seenAt.clear();
    _primed = false;
    _prefs = {};
    if (user == null) {
      _activeUid = null;
      _plugin.cancelAll();
      return;
    }
    _activeUid = user.uid;
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
          .set({'token': token, 'updatedAt': FieldValue.serverTimestamp()});
    } catch (error) {
      debugPrint('HM_FCM_TOKEN_FAILED: $error');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
  }

  void _onForegroundMessage(RemoteMessage message) {
    if (message.data['type'] == 'nudge' &&
        NudgeHaptic.isFresh(message.sentTime)) {
      unawaited(NudgeHaptic.play());
    }
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
        _seenAt[chat.id] =
            chat.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
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
      if (_lifecycle != AppLifecycleState.resumed) continue;
      final started = _startedAt;
      if (started != null &&
          DateTime.now().difference(started) < const Duration(seconds: 4)) {
        continue;
      }
      if (DateTime.now().difference(at) > const Duration(seconds: 8)) {
        continue;
      }
      unawaited(_showForChat(chat, uid));
    }
  }

  Future<void> _showForChat(ChatRoom chat, String uid) async {
    if (chat.isGroup) {
      await showMessage(
        id: chat.id.hashCode,
        sender: chat.groupName.isEmpty ? 'Grup' : chat.groupName,
        preview: chat.lastMessage,
      );
      return;
    }
    final otherId = chat.otherParticipantId(uid);
    var sender = 'Kayıt';
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
            AndroidFlutterLocalNotificationsPlugin
          >()
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
        silent ? 'Hesaplamalar' : 'Kayıtlar',
        channelDescription: silent ? 'Sessiz uyarilar' : 'Kayıt uyarilari',
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
    return showMessage(id: 991991, sender: 'Ahmet', preview: 'Yarın görüşürüz');
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSub?.cancel();
    _chatsSub?.cancel();
    _prefsSub?.cancel();
    _tokenSub?.cancel();
    _foregroundSub?.cancel();
  }
}

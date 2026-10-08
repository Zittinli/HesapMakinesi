import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/chat_service.dart';
import 'services/force_lock_service.dart';
import 'services/notification_service.dart';
import 'services/nudge_haptic.dart';
import 'services/nudge_service.dart';
import 'services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (message.data['type'] == 'nudge' && NudgeHaptic.isFresh(message.sentTime)) {
    await NudgeHaptic.play();
  }
  if (message.data['type'] == 'forceLock') {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(ForceLockService.pendingKey, true);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  final settings = SettingsService();
  final authService = AuthService();
  final chatService = ChatService();
  await settings.load();

  final notificationService = NotificationService(
    settings: settings,
    chatService: chatService,
    authService: authService,
  );
  final nudgeService = NudgeService(
    authService: authService,
    chatService: chatService,
  );
  final forceLockService = ForceLockService(
    authService: authService,
    chatService: chatService,
  );

  runApp(
    HesapMakinesiApp(
      settings: settings,
      authService: authService,
      chatService: chatService,
      notificationService: notificationService,
      nudgeService: nudgeService,
      forceLockService: forceLockService,
    ),
  );
  unawaited(notificationService.start());
  nudgeService.start();
  forceLockService.start();
}

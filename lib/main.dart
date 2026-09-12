import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/chat_service.dart';
import 'services/notification_service.dart';
import 'services/settings_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
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
  await notificationService.start();

  runApp(
    HesapMakinesiApp(
      settings: settings,
      authService: authService,
      chatService: chatService,
      notificationService: notificationService,
    ),
  );
}

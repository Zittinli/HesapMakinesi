import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/privacy_cover.dart';
import 'core/theme/calculator_theme.dart';
import 'features/auth/auth_gate_screen.dart';
import 'features/calculator/calculator_screen.dart';
import 'services/auth_service.dart';
import 'services/auth_log_service.dart';
import 'services/chat_service.dart';
import 'services/notification_service.dart';
import 'services/email_otp_service.dart';
import 'services/moderation_service.dart';
import 'services/settings_service.dart';
import 'services/storage_service.dart';

class HesapMakinesiApp extends StatelessWidget {
  const HesapMakinesiApp({
    super.key,
    required this.settings,
    required this.authService,
    required this.chatService,
    required this.notificationService,
  });

  final SettingsService settings;
  final AuthService authService;
  final ChatService chatService;
  final NotificationService notificationService;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: authService),
        Provider.value(value: chatService),
        Provider(create: (_) => StorageService()),
        Provider(create: (_) => ModerationService()),
        Provider(create: (_) => EmailOtpService()),
        Provider(create: (_) => AuthLogService()),
        Provider<NotificationService>.value(value: notificationService),
      ],
      child: MaterialApp(
        title: 'HesapMakinesi',
        debugShowCheckedModeBanner: false,
        theme: CalculatorTheme.theme,
        builder: (context, child) {
          return PrivacyCover(child: child ?? const SizedBox.shrink());
        },
        home: const RootScreen(),
      ),
    );
  }
}

class RootScreen extends StatelessWidget {
  const RootScreen({super.key});

  void _openMessaging(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AuthGateScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CalculatorScreen(
      onSecretUnlock: () => _openMessaging(context),
    );
  }
}

import 'dart:async';

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
import 'services/nudge_service.dart';
import 'services/force_lock_service.dart';
import 'services/moderation_service.dart';
import 'services/outgoing_queue_service.dart';
import 'services/settings_service.dart';
import 'services/storage_service.dart';

class HesapMakinesiApp extends StatelessWidget {
  const HesapMakinesiApp({
    super.key,
    required this.settings,
    required this.authService,
    required this.chatService,
    required this.notificationService,
    required this.nudgeService,
    required this.forceLockService,
  });

  final SettingsService settings;
  final AuthService authService;
  final ChatService chatService;
  final NotificationService notificationService;
  final NudgeService nudgeService;
  final ForceLockService forceLockService;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: authService),
        Provider.value(value: chatService),
        Provider(create: (_) => StorageService()),
        ChangeNotifierProvider(
          create: (context) => OutgoingQueueService(
            chatService: context.read<ChatService>(),
            storage: context.read<StorageService>(),
            settings: context.read<SettingsService>(),
          ),
        ),
        Provider(create: (_) => ModerationService()),
        Provider(create: (_) => AuthLogService()),
        Provider<NotificationService>.value(value: notificationService),
        ChangeNotifierProvider<NudgeService>.value(value: nudgeService),
        ChangeNotifierProvider<ForceLockService>.value(value: forceLockService),
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

class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  bool _didAutoOpen = false;
  String? _boundQueueUid;

  void _bindOutgoingQueue() {
    final user = context.read<AuthService>().currentUser;
    final queue = context.read<OutgoingQueueService>();
    final uid = user?.uid;
    if (uid == null) {
      if (_boundQueueUid != null) {
        queue.unbind();
        _boundQueueUid = null;
      }
      return;
    }
    if (_boundQueueUid == uid) return;
    _boundQueueUid = uid;
    unawaited(queue.bind(uid));
  }

  void _openMessaging() {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 120),
        reverseTransitionDuration: const Duration(milliseconds: 100),
        pageBuilder: (_, animation, secondaryAnimation) =>
            const AuthGateScreen(),
        transitionsBuilder: (_, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _bindOutgoingQueue();
      if (_didAutoOpen) return;
      final force = context.read<ForceLockService>();
      if (force.trip) {
        force.consumeTrip();
        unawaited(force.clearPending());
        return;
      }
      final settings = context.read<SettingsService>();
      if (!settings.skipCalculator) return;
      _didAutoOpen = true;
      _openMessaging();
    });
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AuthService>().currentUser;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bindOutgoingQueue();
    });
    return CalculatorScreen(onSecretUnlock: _openMessaging);
  }
}

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/moderation_model.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/force_lock_service.dart';
import '../../services/moderation_service.dart';
import '../../services/notification_service.dart';
import '../../services/outgoing_queue_service.dart';
import '../../services/presence_service.dart';
import '../../services/settings_service.dart';
import '../chat/secret_hub_screen.dart';
import 'email_verify_screen.dart';
import 'login_screen.dart';
import 'restricted_screen.dart';

class AuthGateScreen extends StatefulWidget {
  const AuthGateScreen({super.key});

  @override
  State<AuthGateScreen> createState() => _AuthGateScreenState();
}

class _AuthGateScreenState extends State<AuthGateScreen> {
  PresenceService? _presenceService;
  StreamSubscription<AppUser?>? _quickEmojiSub;
  String? _quickEmojiUid;
  String? _stackUid;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _presenceService?.stop();
    _quickEmojiSub?.cancel();
    try {
      context.read<NotificationService>().setHubOpen(false);
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();

    return StreamBuilder<User?>(
      stream: authService.authStateChanges(),
      initialData: authService.currentUser,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;
        final nextUid = user?.uid;
        if (_stackUid != nextUid) {
          final previous = _stackUid;
          _stackUid = nextUid;
          if (previous != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              final navigator = Navigator.of(context);
              if (navigator.canPop()) {
                navigator.popUntil((route) => route.isFirst);
              }
            });
          }
        }
        if (user == null) {
          _presenceService?.stop();
          _presenceService = null;
          _stopQuickEmojis();
          context.read<OutgoingQueueService>().unbind();
          context.read<NotificationService>().setHubOpen(false);
          return const LoginScreen();
        }

        if (authService.requiresEmailVerification) {
          _presenceService?.stop();
          _presenceService = null;
          _stopQuickEmojis();
          context.read<OutgoingQueueService>().unbind();
          context.read<NotificationService>().setHubOpen(false);
          return const EmailVerifyScreen();
        }

        _presenceService ??= PresenceService(
          settings: context.read<SettingsService>(),
        )..start();
        _watchQuickEmojis(user.uid);
        unawaited(context.read<OutgoingQueueService>().bind(user.uid));
        context.read<NotificationService>().setHubOpen(true);

        return _verifiedHome(context, user);
      },
    );
  }

  void _stopQuickEmojis() {
    _quickEmojiSub?.cancel();
    _quickEmojiSub = null;
    _quickEmojiUid = null;
  }

  void _watchQuickEmojis(String uid) {
    if (_quickEmojiUid == uid) return;
    _quickEmojiSub?.cancel();
    _quickEmojiUid = uid;
    final settings = context.read<SettingsService>();
    _quickEmojiSub = context.read<AuthService>().watchUser(uid).listen((user) {
      final emojis = user?.quickEmojis;
      if (emojis == null || emojis.isEmpty) return;
      settings.applyFavoriteEmojis(emojis);
    });
  }

  Widget _verifiedHome(BuildContext context, User user) {
    void exitToCalculator() {
      context.read<NotificationService>().setHubOpen(false);
      _presenceService?.stop();
      _presenceService = null;
      Navigator.of(context).popUntil((route) => route.isFirst);
    }

    final force = context.watch<ForceLockService>();
    if (force.trip) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final service = context.read<ForceLockService>();
        service.consumeTrip();
        unawaited(service.clearPending());
        exitToCalculator();
      });
    }

    final hub = SecretHubScreen(onExitToCalculator: exitToCalculator);

    return StreamBuilder<ModerationStatus>(
      stream: context.read<ModerationService>().watchRestriction(
            userId: user.uid,
            email: user.email ?? '',
          ),
      builder: (context, restriction) {
        final status = restriction.data;
        if (status != null && status.isRestricted()) {
          return RestrictedScreen(
            status: status,
            onExitToCalculator: exitToCalculator,
          );
        }
        return hub;
      },
    );
  }
}

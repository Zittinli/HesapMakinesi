import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../services/notification_service.dart';
import '../../services/presence_service.dart';
import '../chat/secret_hub_screen.dart';
import 'login_screen.dart';

class AuthGateScreen extends StatefulWidget {
  const AuthGateScreen({super.key});

  @override
  State<AuthGateScreen> createState() => _AuthGateScreenState();
}

class _AuthGateScreenState extends State<AuthGateScreen> {
  PresenceService? _presenceService;

  @override
  void dispose() {
    _presenceService?.stop();
    try {
      context.read<NotificationService>().setHubOpen(false);
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.read<AuthService>();

    return StreamBuilder<User?>(
      stream: authService.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          _presenceService?.stop();
          _presenceService = null;
          context.read<NotificationService>().setHubOpen(false);
          return const LoginScreen();
        }

        _presenceService ??= PresenceService()..start();
        context.read<NotificationService>().setHubOpen(true);

        return SecretHubScreen(
          onExitToCalculator: () {
            context.read<NotificationService>().setHubOpen(false);
            _presenceService?.stop();
            _presenceService = null;
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
        );
      },
    );
  }
}

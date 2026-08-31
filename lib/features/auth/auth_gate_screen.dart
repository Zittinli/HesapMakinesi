import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/admin_config.dart';
import '../../models/moderation_model.dart';
import '../../services/auth_service.dart';
import '../../services/moderation_service.dart';
import '../../services/notification_service.dart';
import '../../services/presence_service.dart';
import '../../services/settings_service.dart';
import '../../models/user_model.dart';
import '../chat/secret_hub_screen.dart';
import '../settings/admin_home_screen.dart';
import 'email_code_screen.dart';
import 'login_screen.dart';
import 'restricted_screen.dart';

class AuthGateScreen extends StatefulWidget {
  const AuthGateScreen({super.key});

  @override
  State<AuthGateScreen> createState() => _AuthGateScreenState();
}

class _AuthGateScreenState extends State<AuthGateScreen> {
  PresenceService? _presenceService;

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

        return StreamBuilder<AppUser?>(
          stream: authService.watchUser(user.uid),
          builder: (context, userSnap) {
            if (!userSnap.hasData &&
                userSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                backgroundColor: Color(0xFF0B0B0B),
                body: Center(
                  child: CircularProgressIndicator(color: Colors.white24),
                ),
              );
            }
            final profile = userSnap.data;
            final needsOtp = profile?.needsEmailOtp == true &&
                !AdminConfig.isAdminEmail(user.email);
            if (needsOtp) {
              _presenceService?.stop();
              _presenceService = null;
              context.read<NotificationService>().setHubOpen(false);
              return const EmailCodeScreen();
            }

            _presenceService ??= PresenceService(
              settings: context.read<SettingsService>(),
            )..start();
            context.read<NotificationService>().setHubOpen(true);

            return _verifiedHome(context, user);
          },
        );
      },
    );
  }

  Widget _verifiedHome(BuildContext context, User user) {
    void exitToCalculator() {
      context.read<NotificationService>().setHubOpen(false);
      _presenceService?.stop();
      _presenceService = null;
      Navigator.of(context).popUntil((route) => route.isFirst);
    }

    if (AdminConfig.isAdminEmail(user.email)) {
      return AdminHomeScreen(onExitToCalculator: exitToCalculator);
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

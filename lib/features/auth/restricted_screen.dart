import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/moderation_model.dart';
import '../../services/auth_service.dart';
import '../settings/settings_screen.dart';

class RestrictedScreen extends StatelessWidget {
  const RestrictedScreen({
    super.key,
    required this.status,
    this.onExitToCalculator,
  });

  final ModerationStatus status;
  final VoidCallback? onExitToCalculator;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B0B),
        foregroundColor: Colors.white70,
        elevation: 0,
        title: const Text('Hesap kisitli'),
        leading: onExitToCalculator == null
            ? null
            : IconButton(
                icon: const Icon(Icons.calculate_outlined),
                onPressed: onExitToCalculator,
              ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.lock_outline, color: Color(0xFFFF8A80), size: 42),
            const SizedBox(height: 16),
            Text(
              status.label,
              style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.4),
            ),
            if (status.reason.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                status.reason,
                style: const TextStyle(color: Colors.white38, fontSize: 13),
              ),
            ],
            const Spacer(),
            OutlinedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white24),
              ),
              child: const Text('Hesabi sil'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => context.read<AuthService>().signOut(),
              child: const Text('Cikis yap', style: TextStyle(color: Colors.white38)),
            ),
          ],
        ),
      ),
    );
  }
}

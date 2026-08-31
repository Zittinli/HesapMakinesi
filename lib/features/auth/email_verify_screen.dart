import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';

/// Kayit sonrasi Firebase'in gonderdigi dogrulama baglantisini bekler.
class EmailVerifyScreen extends StatefulWidget {
  const EmailVerifyScreen({super.key});

  @override
  State<EmailVerifyScreen> createState() => _EmailVerifyScreenState();
}

class _EmailVerifyScreenState extends State<EmailVerifyScreen> {
  Timer? _poller;
  bool _isChecking = false;
  bool _isResending = false;
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    _poller = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _check(silent: true),
    );
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  Future<void> _check({bool silent = false}) async {
    if (_isChecking) return;
    if (!silent) {
      setState(() {
        _isChecking = true;
        _error = null;
        _info = null;
      });
    } else {
      _isChecking = true;
    }

    try {
      final verified =
          await context.read<AuthService>().refreshEmailVerified();
      if (!mounted) return;
      if (!verified && !silent) {
        setState(() => _error = 'Adres henuz dogrulanmamis. Postani kontrol et.');
      }
    } catch (_) {
      if (mounted && !silent) {
        setState(() => _error = 'Durum kontrol edilemedi. Tekrar dene.');
      }
    } finally {
      _isChecking = false;
      if (mounted && !silent) setState(() {});
    }
  }

  Future<void> _resend() async {
    setState(() {
      _isResending = true;
      _error = null;
      _info = null;
    });
    try {
      await context.read<AuthService>().sendVerificationEmail();
      if (mounted) {
        setState(() => _info = 'Dogrulama baglantisi tekrar gonderildi.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Baglanti gonderilemedi. Birazdan tekrar dene.');
      }
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = context.read<AuthService>().currentUser?.email ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B0B),
        foregroundColor: Colors.white70,
        elevation: 0,
        title: const Text(
          'E-posta onayi',
          style: TextStyle(fontWeight: FontWeight.w400),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.read<AuthService>().signOut(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.mark_email_unread_outlined,
              color: Colors.white24,
              size: 56,
            ),
            const SizedBox(height: 20),
            Text(
              email.isEmpty
                  ? 'Adresine bir dogrulama baglantisi gonderildi.'
                  : '$email adresine bir dogrulama baglantisi gonderildi.',
              style: const TextStyle(color: Colors.white70, height: 1.4),
            ),
            const SizedBox(height: 8),
            const Text(
              'Postandaki baglantiya dokun, sonra bu ekrana don. '
              'Onay gelince otomatik olarak devam eder.',
              style: TextStyle(color: Colors.white38, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 24),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Color(0xFFFF8A80)),
                ),
              ),
            if (_info != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _info!,
                  style: const TextStyle(color: Color(0xFFA5D6A7)),
                ),
              ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2A2A2A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _isChecking ? null : () => _check(),
              child: _isChecking
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white54,
                      ),
                    )
                  : const Text('Dogruladim, devam et'),
            ),
            TextButton(
              onPressed: _isResending ? null : _resend,
              style: TextButton.styleFrom(foregroundColor: Colors.white54),
              child: Text(
                _isResending ? 'Gonderiliyor...' : 'Baglantiyi tekrar gonder',
              ),
            ),
            TextButton(
              onPressed: () => context.read<AuthService>().signOut(),
              style: TextButton.styleFrom(foregroundColor: Colors.white38),
              child: const Text('Giris ekranina don'),
            ),
          ],
        ),
      ),
    );
  }
}

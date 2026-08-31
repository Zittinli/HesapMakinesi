import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../services/email_otp_service.dart';

class EmailCodeScreen extends StatefulWidget {
  const EmailCodeScreen({super.key});

  @override
  State<EmailCodeScreen> createState() => _EmailCodeScreenState();
}

class _EmailCodeScreenState extends State<EmailCodeScreen> {
  final _codeController = TextEditingController();
  bool _isVerifying = false;
  bool _isResending = false;
  bool _sentOnce = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sendInitial());
  }

  Future<void> _sendInitial() async {
    if (_sentOnce || !mounted) return;
    _sentOnce = true;
    try {
      await context.read<EmailOtpService>().sendCode();
    } on EmailOtpException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Kod gonderilemedi. Tekrar dene.');
      }
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _error = '6 haneli kodu gir.');
      return;
    }
    setState(() {
      _isVerifying = true;
      _error = null;
    });
    try {
      final otp = context.read<EmailOtpService>();
      final auth = context.read<AuthService>();
      await otp.verifyCode(code);
      if (!mounted) return;
      await auth.completeEmailVerification();
    } on EmailOtpException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Kod dogrulanamadi.');
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _isResending = true;
      _error = null;
    });
    try {
      await context.read<EmailOtpService>().sendCode();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Yeni kod gonderildi.')),
        );
      }
    } on EmailOtpException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Kod tekrar gonderilemedi.');
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
        title: const Text('E-posta onayi', style: TextStyle(fontWeight: FontWeight.w400)),
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
            Text(
              email.isEmpty
                  ? 'E-postana 6 haneli onay kodu gonderildi.'
                  : '$email adresine 6 haneli onay kodu gonderildi.',
              style: const TextStyle(color: Colors.white70, height: 1.4),
            ),
            const SizedBox(height: 8),
            const Text(
              'Kodu girmeden kayit tamamlanmaz.',
              style: TextStyle(color: Colors.white38, fontSize: 13),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                letterSpacing: 8,
              ),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                counterText: '',
                hintText: '------',
                hintStyle: const TextStyle(color: Colors.white24, letterSpacing: 8),
                filled: true,
                fillColor: const Color(0xFF1A1A1A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _verify(),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Color(0xFFFF8A80)),
                ),
              ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2A2A2A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _isVerifying ? null : _verify,
              child: _isVerifying
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white54,
                      ),
                    )
                  : const Text('Onayla ve gir'),
            ),
            TextButton(
              onPressed: _isResending ? null : _resend,
              style: TextButton.styleFrom(foregroundColor: Colors.white54),
              child: Text(_isResending ? 'Gonderiliyor...' : 'Kodu tekrar gonder'),
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

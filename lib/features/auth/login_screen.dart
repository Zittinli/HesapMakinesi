import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await context.read<AuthService>().signIn(
            _emailController.text.trim(),
            _passwordController.text,
          );
    } on FirebaseAuthException catch (error) {
      setState(() => _error = _loginError(error.code));
    } catch (error) {
      setState(() => _error = 'Giris basarisiz. Bilgilerinizi kontrol edin.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Sifre sifirlama icin e-posta yaz.');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await context.read<AuthService>().sendPasswordReset(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sifre sifirlama baglantisi e-postana gonderildi. Gelen kutusu ve spam klasorunu kontrol et.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Baglanti gonderilemedi. E-postayi kontrol et.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _loginError(String code) {
    switch (code) {
      case 'wrong-password':
      case 'invalid-credential':
      case 'invalid-login-credentials':
        return 'E-posta veya sifre yanlis.';
      case 'user-not-found':
        return 'Bu e-posta ile hesap yok.';
      case 'user-disabled':
        return 'Bu hesap kapatilmis.';
      case 'too-many-requests':
        return 'Cok fazla deneme. Biraz bekleyip tekrar dene.';
      case 'network-request-failed':
        return 'Ag hatasi. Baglantini kontrol et.';
      default:
        return 'Giris basarisiz. Bilgilerinizi kontrol edin.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B0B),
        foregroundColor: Colors.white70,
        elevation: 0,
        title: const Text('Oturum', style: TextStyle(fontWeight: FontWeight.w400)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(color: Colors.white),
                decoration: _fieldDecoration('E-posta'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'E-posta gerekli';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: _fieldDecoration('Sifre'),
                validator: (value) {
                  if (value == null || value.length < 6) {
                    return 'Sifre en az 6 karakter olmali';
                  }
                  return null;
                },
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
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2A2A2A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _isLoading ? null : _submit,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white54,
                        ),
                      )
                    : const Text('Devam'),
              ),
              TextButton(
                onPressed: _isLoading ? null : _resetPassword,
                style: TextButton.styleFrom(foregroundColor: Colors.white54),
                child: const Text('Sifremi unuttum'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RegisterScreen()),
                  );
                },
                style: TextButton.styleFrom(foregroundColor: Colors.white54),
                child: const Text('Yeni kayit'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white54),
      filled: true,
      fillColor: const Color(0xFF1A1A1A),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
    );
  }
}

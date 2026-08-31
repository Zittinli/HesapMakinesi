import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/registration_terms.dart';
import '../../services/auth_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _acceptedTerms = false;
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_acceptedTerms) {
      setState(() => _error = 'Kayit icin gizlilik politikasini onaylaman gerekir.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await context.read<AuthService>().signUp(
            email: _emailController.text.trim(),
            password: _passwordController.text,
            displayName: _nameController.text.trim(),
            acceptedTerms: true,
          );
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      setState(() => _error = 'Kayit basarisiz. Bilgilerinizi kontrol edin.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _openPrivacyPolicy() async {
    var opened = false;
    try {
      opened = await RegistrationTerms.openPrivacyPolicy();
    } catch (_) {}
    if (opened || !mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF161616),
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: SingleChildScrollView(
            child: Text(
              RegistrationTerms.fullText,
              style: const TextStyle(color: Colors.white70, height: 1.45),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B0B),
        foregroundColor: Colors.white70,
        elevation: 0,
        title: const Text('Yeni kayit', style: TextStyle(fontWeight: FontWeight.w400)),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextFormField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white),
              decoration: _fieldDecoration('Gorunen ad'),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Ad gerekli';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: Colors.white),
              decoration: _fieldDecoration('E-posta'),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'E-posta gerekli';
                }
                if (!value.contains('@')) {
                  return 'Gecerli bir e-posta yaz';
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
            const SizedBox(height: 20),
            Text(
              RegistrationTerms.summary,
              style: const TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
            ),
            TextButton(
              onPressed: _openPrivacyPolicy,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white54,
                alignment: Alignment.centerLeft,
                padding: EdgeInsets.zero,
              ),
              child: const Text('Gizlilik politikasini oku'),
            ),
            CheckboxListTile(
              value: _acceptedTerms,
              onChanged: (value) => setState(() => _acceptedTerms = value ?? false),
              activeColor: Colors.white70,
              checkColor: Colors.black,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                RegistrationTerms.checkboxLabel,
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ),
            const SizedBox(height: 12),
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
              onPressed: (_isLoading || !_acceptedTerms) ? null : _submit,
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white54,
                      ),
                    )
                  : const Text('Kod gonder ve kayit ol'),
            ),
          ],
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

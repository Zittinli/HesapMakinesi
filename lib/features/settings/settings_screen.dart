import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/admin_config.dart';
import '../../core/chat_format.dart';
import '../../core/registration_terms.dart';
import '../../core/slide_from_right_route.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/release_notes_service.dart';
import 'admin_home_screen.dart';
import 'release_history_screen.dart';
import 'notification_settings_screen.dart';
import 'privacy_settings_screen.dart';
import 'theme_settings_screen.dart';
import 'unlock_code_settings_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.onExitToCalculator});

  final VoidCallback? onExitToCalculator;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Future<void> _deleteAccount() async {
    final passwordController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF161616),
          title: const Text(
            'Hesabı sil',
            style: TextStyle(color: Colors.white70),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Hesabınız, mesajlarınız ve kişisel verileriniz silinir. Bu geri alınamaz.',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Şifrenizi yazın',
                  hintStyle: TextStyle(color: Colors.white30),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                'Kalıcı sil',
                style: TextStyle(color: Color(0xFFFF8A80)),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      passwordController.dispose();
      return;
    }
    try {
      await context.read<AuthService>().deleteAccount(passwordController.text);
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      final message =
          error.code == 'wrong-password' || error.code == 'invalid-credential'
          ? 'Şifre yanlış.'
          : 'Hesap silinemedi. Tekrar giriş yapıp deneyin.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hesap silinemedi. Tekrar deneyin.')),
      );
    } finally {
      passwordController.dispose();
    }
  }

  void _open(Widget page) {
    Navigator.of(context).push(
      SlideFromRightPageRoute<void>(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = context.read<AuthService>().currentUser?.email;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B0B),
        foregroundColor: Colors.white70,
        elevation: 0,
        title: const Text(
          'Ayarlar',
          style: TextStyle(fontWeight: FontWeight.w400, letterSpacing: 0.5),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          const _DisplayNameSettings(),
          const SizedBox(height: 8),
          const Divider(color: Color(0xFF222222)),
          const SizedBox(height: 8),
          _SettingsLinkTile(
            title: 'Gizlilik',
            subtitle: 'Kim neleri görebilir, sohbet nasıl kapanır.',
            onTap: () => _open(
              PrivacySettingsScreen(
                onExitToCalculator: widget.onExitToCalculator,
              ),
            ),
          ),
          _SettingsLinkTile(
            title: 'Bildirim görünümü',
            subtitle: 'Kilit ekranı ve bildirim çubuğunda görünüm.',
            onTap: () => _open(const NotificationSettingsScreen()),
          ),
          _SettingsLinkTile(
            title: 'Tema',
            subtitle: 'Hesap makinesi görünümü.',
            onTap: () => _open(const ThemeSettingsScreen()),
          ),
          _SettingsLinkTile(
            title: 'Giriş kodu',
            subtitle: 'Uygulamaya giriş kodu.',
            onTap: () => _open(const UnlockCodeSettingsScreen()),
          ),
          const SizedBox(height: 8),
          const Divider(color: Color(0xFF222222)),
          const SizedBox(height: 16),
          _UpdateNotes(isAdmin: AdminConfig.isAdminEmail(email)),
          if (AdminConfig.isAdminEmail(email)) ...[
            const SizedBox(height: 8),
            const Divider(color: Color(0xFF222222)),
            _SettingsLinkTile(
              title: 'Önceki güncellemeler',
              subtitle: 'Eski sürüm notları.',
              onTap: () => _open(const ReleaseHistoryScreen()),
            ),
            const SizedBox(height: 8),
            const Divider(color: Color(0xFF222222)),
            const SizedBox(height: 16),
            const Text(
              'Yönetim',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 6),
            const Text(
              'Bildirilenler ve girişler.',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white24),
              ),
              onPressed: () {
                Navigator.of(context).push(
                  SlideFromRightPageRoute(
                    builder: (_) => AdminHomeScreen(
                      onExitToCalculator: () {
                        Navigator.of(
                          context,
                        ).popUntil((route) => route.isFirst);
                      },
                    ),
                  ),
                );
              },
              child: const Text('Yönetim paneli'),
            ),
          ],
          const SizedBox(height: 8),
          const Divider(color: Color(0xFF222222)),
          const SizedBox(height: 16),
          const Text(
            'Hesap',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 6),
          const Text(
            'Hesabınızı ve bu uygulamadaki kişisel verilerinizi kalıcı siler.',
            style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => RegistrationTerms.openPrivacyPolicy(),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white54,
              alignment: Alignment.centerLeft,
              padding: EdgeInsets.zero,
            ),
            child: const Text('Gizlilik politikası'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFFF8A80),
              side: const BorderSide(color: Color(0xFF5A2A2A)),
            ),
            onPressed: _deleteAccount,
            child: const Text('Hesabı sil'),
          ),
        ],
      ),
    );
  }
}

class _SettingsLinkTile extends StatelessWidget {
  const _SettingsLinkTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: const TextStyle(color: Colors.white70)),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Colors.white38, fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.white38),
      onTap: onTap,
    );
  }
}

class _UpdateNotes extends StatefulWidget {
  const _UpdateNotes({required this.isAdmin});

  final bool isAdmin;

  @override
  State<_UpdateNotes> createState() => _UpdateNotesState();
}

class _UpdateNotesState extends State<_UpdateNotes> {
  final _service = ReleaseNotesService();
  late final Stream<ReleaseNotes> _stream;
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  bool _dirty = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _stream = _service.watch();
    _titleController = TextEditingController(text: ReleaseNotes.defaults.title);
    _bodyController = TextEditingController(text: ReleaseNotes.defaults.body);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _fillIfClean(ReleaseNotes notes) {
    if (_dirty || notes.items.isEmpty) return;
    if (_titleController.text != notes.title) {
      _titleController.text = notes.title;
    }
    if (_bodyController.text != notes.body) {
      _bodyController.text = notes.body;
    }
  }

  ReleaseNotes _visibleNotes(ReleaseNotes? data) {
    if (data == null || data.items.isEmpty) return ReleaseNotes.defaults;
    return data;
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _service.save(
        title: _titleController.text,
        body: _bodyController.text,
      );
      if (!mounted) return;
      setState(() => _dirty = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Güncelleme notları kaydedildi.')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Notlar kaydedilemedi.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ReleaseNotes>(
      initialData: ReleaseNotes.defaults,
      stream: _stream,
      builder: (context, snapshot) {
        final notes = snapshot.hasError
            ? ReleaseNotes.defaults
            : _visibleNotes(snapshot.data);
        if (widget.isAdmin) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _fillIfClean(notes);
          });
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ReadOnlyNotes(notes: notes),
            if (widget.isAdmin) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _titleController,
                style: const TextStyle(color: Colors.white70, fontSize: 16),
                maxLength: 80,
                onChanged: (_) => setState(() => _dirty = true),
                decoration: const InputDecoration(
                  counterText: '',
                  hintText: 'Başlık',
                  hintStyle: TextStyle(color: Colors.white30),
                  filled: true,
                  fillColor: Color(0xFF1A1A1A),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Her satır bir madde.',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _bodyController,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.4,
                ),
                maxLength: 8000,
                maxLines: 12,
                minLines: 8,
                onChanged: (_) => setState(() => _dirty = true),
                decoration: const InputDecoration(
                  counterText: '',
                  filled: true,
                  fillColor: Color(0xFF1A1A1A),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(color: Color(0xFFFF8A80)),
                ),
              ],
              const SizedBox(height: 10),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2A2A2A),
                  foregroundColor: Colors.white,
                ),
                onPressed: _saving || !_dirty ? null : _save,
                child: Text(_saving ? 'Kaydediliyor...' : 'Notları kaydet'),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ReadOnlyNotes extends StatelessWidget {
  const _ReadOnlyNotes({required this.notes});

  final ReleaseNotes notes;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          notes.title,
          style: const TextStyle(color: Colors.white70, fontSize: 16),
        ),
        const SizedBox(height: 10),
        for (final item in notes.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '•  ',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                Expanded(
                  child: Text(
                    item,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DisplayNameSettings extends StatefulWidget {
  const _DisplayNameSettings();

  @override
  State<_DisplayNameSettings> createState() => _DisplayNameSettingsState();
}

class _DisplayNameSettingsState extends State<_DisplayNameSettings> {
  late final TextEditingController _nameController;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save(AppUser? profile) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<AuthService>().updateDisplayName(_nameController.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Görünen ad güncellendi.')),
        );
      }
    } on FirebaseAuthException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Ad güncellenemedi.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final uid = auth.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<AppUser?>(
      stream: auth.watchUser(uid),
      builder: (context, snapshot) {
        final profile = snapshot.data;
        if (profile != null && _nameController.text.isEmpty) {
          _nameController.text = profile.displayName;
        }
        final cooldown = profile?.displayNameCooldown;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Görünen ad',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 6),
            const Text(
              'Sohbette e-posta yerine bu ad görünür. En erken saatte bir değişir.',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF1A1A1A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            if (cooldown != null) ...[
              const SizedBox(height: 8),
              Text(
                'Sonraki değişiklik: ${ChatFormat.eventDateTime(DateTime.now().add(cooldown))}',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Color(0xFFFF8A80))),
            ],
            const SizedBox(height: 10),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2A2A2A),
                foregroundColor: Colors.white,
              ),
              onPressed: _saving ? null : () => _save(profile),
              child: Text(_saving ? 'Kaydediliyor...' : 'Adı kaydet'),
            ),
          ],
        );
      },
    );
  }
}

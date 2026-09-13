import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/admin_config.dart';
import '../../core/chat_format.dart';
import '../../core/registration_terms.dart';
import '../../core/secret_config.dart';
import '../../core/theme/calculator_palette.dart';
import '../../models/notification_look.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/notification_service.dart';
import '../../services/settings_service.dart';
import 'admin_home_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _leftController;
  late final TextEditingController _rightController;
  late String _operator;
  String? _codeError;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsService>();
    _leftController = TextEditingController(text: settings.unlockLeft);
    _rightController = TextEditingController(text: settings.unlockRight);
    _operator = settings.unlockOperator;
  }

  @override
  void dispose() {
    _leftController.dispose();
    _rightController.dispose();
    super.dispose();
  }

  Future<void> _saveCode() async {
    final settings = context.read<SettingsService>();
    final error = await settings.setUnlockCode(
      left: _leftController.text,
      operator: _operator,
      right: _rightController.text,
    );
    if (!mounted) return;
    setState(() => _codeError = error);
    if (error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Giris kodu: ${settings.unlockLabel} =')),
      );
    }
  }

  Future<void> _deleteAccount() async {
    final passwordController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF161616),
          title: const Text(
            'Hesabi sil',
            style: TextStyle(color: Colors.white70),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Hesabiniz, mesajlariniz ve kisisel verileriniz silinir. Bu geri alinamaz.',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Sifrenizi yazin',
                  hintStyle: TextStyle(color: Colors.white30),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgec'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                'Kalici sil',
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
          ? 'Sifre yanlis.'
          : 'Hesap silinemedi. Tekrar giris yapip deneyin.';
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

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final email = context.read<AuthService>().currentUser?.email;
    final preview = NotificationCopy.of(
      look: settings.notificationLook,
      sender: 'Ahmet',
      preview: 'Yarin gorusuruz',
    );

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
          const Text(
            'Giris kodu',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 6),
          const Text(
            'Master kod her cihazda calisir: 1231 × 3112. Istegine bagli ekstra kod da ayni anda gecerli kalir.',
            style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _numberField(_leftController, 'Sol sayi')),
              const SizedBox(width: 8),
              Expanded(child: _numberField(_rightController, 'Sag sayi')),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: SettingsService.allowedOperators.map((op) {
              final selected = _operator == op;
              return ChoiceChip(
                label: Text(op),
                selected: selected,
                onSelected: (_) => setState(() => _operator = op),
                selectedColor: const Color(0xFF2A2A2A),
                backgroundColor: const Color(0xFF161616),
                labelStyle: TextStyle(
                  color: selected ? Colors.white : Colors.white54,
                ),
                side: BorderSide(
                  color: selected ? Colors.white24 : Colors.white10,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Text(
            'Su an: ${_leftController.text.isEmpty ? settings.unlockLeft : _leftController.text} $_operator ${_rightController.text.isEmpty ? settings.unlockRight : _rightController.text} =',
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          if (_codeError != null) ...[
            const SizedBox(height: 8),
            Text(
              _codeError!,
              style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 13),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2A2A2A),
              foregroundColor: Colors.white,
            ),
            onPressed: _saveCode,
            child: const Text('Kodu kaydet'),
          ),
          TextButton(
            onPressed: () async {
              _leftController.text = SecretConfig.secretLeft;
              _rightController.text = SecretConfig.secretRight;
              setState(() => _operator = SecretConfig.secretOperator);
              await _saveCode();
            },
            child: const Text(
              'Varsayilana don (3112 × 1231)',
              style: TextStyle(color: Colors.white38),
            ),
          ),
          const SizedBox(height: 20),
          const Divider(color: Color(0xFF222222)),
          const SizedBox(height: 16),
          const Text(
            'Hesap makinesi temasi',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            'Secili: ${settings.calculatorSkin.label}',
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 8),
          ...CalculatorSkin.values.map((skin) {
            return RadioListTile<CalculatorSkin>(
              value: skin,
              groupValue: settings.calculatorSkin,
              onChanged: skin.available
                  ? (value) {
                      if (value != null) settings.setCalculatorSkin(value);
                    }
                  : null,
              activeColor: Colors.white70,
              contentPadding: EdgeInsets.zero,
              title: Text(
                skin.label,
                style: TextStyle(
                  color: skin.available ? Colors.white70 : Colors.white38,
                ),
              ),
              subtitle: Text(
                skin.available ? 'Kullanilabilir' : 'Yakinda eklenecek',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            );
          }),
          const SizedBox(height: 8),
          const Divider(color: Color(0xFF222222)),
          const SizedBox(height: 16),
          const _DisplayNameSettings(),
          const SizedBox(height: 8),
          const Divider(color: Color(0xFF222222)),
          const SizedBox(height: 16),
          const Text(
            'Gizlilik',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 6),
          const Text(
            'Kapatinca sen de gondermezsin, karsi taraftakini de gormezsin.',
            style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: settings.screenProtectionEnabled,
            onChanged: settings.setScreenProtectionEnabled,
            title: const Text(
              'Ekran korumasi',
              style: TextStyle(color: Colors.white70),
            ),
            subtitle: const Text(
              'Ekran goruntusu, kayit, paylasim ve son uygulamalar '
              'onizlemesinde icerigi gizler.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            activeColor: Colors.white70,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: settings.typingEnabled,
            onChanged: settings.setTypingEnabled,
            title: const Text(
              'Yaziyor bilgisi',
              style: TextStyle(color: Colors.white70),
            ),
            subtitle: const Text(
              'Karsi taraf yazarken Yaziyor... gosterilir.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            activeColor: Colors.white70,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: settings.readReceiptsEnabled,
            onChanged: settings.setReadReceiptsEnabled,
            title: const Text(
              'Goruldu tikleri',
              style: TextStyle(color: Colors.white70),
            ),
            subtitle: const Text(
              'Cift mavi tik: mesaj goruldu. Kapaliysa tik guncellenmez.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            activeColor: Colors.white70,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: settings.lastSeenEnabled,
            onChanged: settings.setLastSeenEnabled,
            title: const Text(
              'Son gorulme / son aktif',
              style: TextStyle(color: Colors.white70),
            ),
            subtitle: const Text(
              'Aktif, son gorulme ve son aktif bilgisi paylasilir.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            activeColor: Colors.white70,
          ),
          const SizedBox(height: 8),
          const Divider(color: Color(0xFF222222)),
          const SizedBox(height: 16),
          const Text(
            'Bildirim gorunumu',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 6),
          const Text(
            'Kilit ekraninda ve bildirim cubugunda boyle gorunur.',
            style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 14),
          _NotificationPreview(copy: preview),
          const SizedBox(height: 12),
          ...NotificationLook.values.map((look) {
            return RadioListTile<NotificationLook>(
              value: look,
              groupValue: settings.notificationLook,
              onChanged: (value) {
                if (value != null) settings.setNotificationLook(value);
              },
              activeColor: Colors.white70,
              contentPadding: EdgeInsets.zero,
              title: Text(
                look.label,
                style: const TextStyle(color: Colors.white70, fontSize: 15),
              ),
              subtitle: Text(
                look.hint,
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            );
          }),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: settings.soundEnabled,
            onChanged: settings.notificationLook == NotificationLook.off
                ? null
                : settings.setSoundEnabled,
            title: const Text('Ses', style: TextStyle(color: Colors.white70)),
            activeColor: Colors.white70,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: settings.vibrateEnabled,
            onChanged: settings.notificationLook == NotificationLook.off
                ? null
                : settings.setVibrateEnabled,
            title: const Text(
              'Titresim',
              style: TextStyle(color: Colors.white70),
            ),
            activeColor: Colors.white70,
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: const BorderSide(color: Colors.white24),
            ),
            onPressed: settings.notificationLook == NotificationLook.off
                ? null
                : () => context.read<NotificationService>().showPreview(),
            child: const Text('Ornek bildirimi goster'),
          ),
          if (AdminConfig.isAdminEmail(email)) ...[
            const SizedBox(height: 20),
            const Divider(color: Color(0xFF222222)),
            const SizedBox(height: 16),
            const Text(
              'Yonetim',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 6),
            const Text(
              'Bildirilen kullanicilar ve giris kayitlari. Firebase Console > Firestore > reports ve authEvents koleksiyonlarinda da durur.',
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
                  MaterialPageRoute(
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
              child: const Text('Yonetim paneli'),
            ),
          ],
          const SizedBox(height: 20),
          const Divider(color: Color(0xFF222222)),
          const SizedBox(height: 16),
          const Text(
            'Hesap',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 6),
          const Text(
            'Hesabinizi ve bu uygulamadaki kisisel verilerinizi kalici siler.',
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
            child: const Text('Gizlilik politikasi'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFFF8A80),
              side: const BorderSide(color: Color(0xFF5A2A2A)),
            ),
            onPressed: _deleteAccount,
            child: const Text('Hesabi sil'),
          ),
        ],
      ),
    );
  }

  Widget _numberField(TextEditingController controller, String hint) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      style: const TextStyle(color: Colors.white),
      cursorColor: Colors.white54,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white30),
        filled: true,
        fillColor: const Color(0xFF1A1A1A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _NotificationPreview extends StatelessWidget {
  const _NotificationPreview({required this.copy});

  final NotificationCopy? copy;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF161616),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: copy == null
          ? const Text(
              'Bildirim kapali. Cihazda bir sey gorunmez.',
              style: TextStyle(color: Colors.white38, fontSize: 13),
            )
          : Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.calculate_outlined,
                    color: Colors.white70,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        copy!.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        copy!.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
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
          const SnackBar(content: Text('Gorunen ad guncellendi.')),
        );
      }
    } on FirebaseAuthException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Ad guncellenemedi.');
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
              'Gorunen ad',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 6),
            const Text(
              'Sohbette e-posta yerine bu ad gorunur. En erken saatte bir degisir.',
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
                'Sonraki degisiklik: ${ChatFormat.eventDateTime(DateTime.now().add(cooldown))}',
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
              child: Text(_saving ? 'Kaydediliyor...' : 'Adi kaydet'),
            ),
          ],
        );
      },
    );
  }
}

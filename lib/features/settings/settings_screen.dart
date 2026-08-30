import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/secret_config.dart';
import '../../models/notification_look.dart';
import '../../services/notification_service.dart';
import '../../services/settings_service.dart';

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

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
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
            'Hesap makinesinde bu islemi yapinca kayitlar acilir. Varsayilan 3112 × 1231.',
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
            title: const Text(
              'Ses',
              style: TextStyle(color: Colors.white70),
            ),
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

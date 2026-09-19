import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/slide_from_right_route.dart';
import '../../services/settings_service.dart';
import 'nudge_settings_screen.dart';

class PrivacySettingsScreen extends StatelessWidget {
  const PrivacySettingsScreen({super.key, this.onExitToCalculator});

  final VoidCallback? onExitToCalculator;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B0B),
        foregroundColor: Colors.white70,
        elevation: 0,
        title: const Text(
          'Gizlilik',
          style: TextStyle(fontWeight: FontWeight.w400),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Dürtme',
              style: TextStyle(color: Colors.white70),
            ),
            subtitle: const Text(
              'Titreşim gönder.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.white38),
            onTap: () {
              Navigator.of(context).push(
                SlideFromRightPageRoute<void>(
                  builder: (_) => NudgeSettingsScreen(
                    onExitToCalculator: onExitToCalculator,
                  ),
                ),
              );
            },
          ),
          const _IdleTimeoutField(),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: settings.screenProtectionEnabled,
            onChanged: settings.setScreenProtectionEnabled,
            title: const Text(
              'Ekran koruması',
              style: TextStyle(color: Colors.white70),
            ),
            subtitle: const Text(
              'Ekranı gizler.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            activeColor: Colors.white70,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: settings.typingEnabled,
            onChanged: settings.setTypingEnabled,
            title: const Text(
              'Yazıyor bilgisi',
              style: TextStyle(color: Colors.white70),
            ),
            subtitle: const Text(
              'Yazıyor... gösterilir.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            activeColor: Colors.white70,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: settings.readReceiptsEnabled,
            onChanged: settings.setReadReceiptsEnabled,
            title: const Text(
              'Görüldü tikleri',
              style: TextStyle(color: Colors.white70),
            ),
            subtitle: const Text(
              'Okundu bilgisi.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            activeColor: Colors.white70,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: settings.lastSeenEnabled,
            onChanged: settings.setLastSeenEnabled,
            title: const Text(
              'Son görülme / son aktif',
              style: TextStyle(color: Colors.white70),
            ),
            subtitle: const Text(
              'Son görülmen paylaşılır.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            activeColor: Colors.white70,
          ),
        ],
      ),
    );
  }
}

class _IdleTimeoutField extends StatefulWidget {
  const _IdleTimeoutField();

  @override
  State<_IdleTimeoutField> createState() => _IdleTimeoutFieldState();
}

class _IdleTimeoutFieldState extends State<_IdleTimeoutField> {
  static const _presets = [60, 150, 300, 600];
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.text =
          '${context.read<SettingsService>().chatIdleSeconds}';
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save([int? seconds]) async {
    final settings = context.read<SettingsService>();
    final parsed =
        seconds ?? int.tryParse(_controller.text.trim().replaceAll(',', ''));
    if (parsed == null) {
      _controller.text = '${settings.chatIdleSeconds}';
      return;
    }
    await settings.setChatIdleSeconds(parsed);
    if (!mounted) return;
    _controller.text = '${settings.chatIdleSeconds}';
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
  }

  String _presetLabel(int seconds) {
    if (seconds % 60 == 0) return '${seconds ~/ 60} dk';
    return '${seconds / 60} dk';
  }

  @override
  Widget build(BuildContext context) {
    final selected = context.watch<SettingsService>().chatIdleSeconds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Sohbet zaman aşımı',
          style: TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: 6),
        const Text(
          'Hareketsiz kalınca kapanır.',
          style: TextStyle(color: Colors.white38, fontSize: 12),
        ),
        const SizedBox(height: 10),
        Focus(
          onFocusChange: (hasFocus) {
            if (!hasFocus) _save();
          },
          child: TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              suffixText: 'sn',
              suffixStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: const Color(0xFF1A1A1A),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
            onEditingComplete: _save,
            onSubmitted: (_) => _save(),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final seconds in _presets)
              ChoiceChip(
                label: Text(_presetLabel(seconds)),
                selected: selected == seconds,
                selectedColor: const Color(0xFF2A2A2A),
                backgroundColor: const Color(0xFF161616),
                labelStyle: TextStyle(
                  color: selected == seconds ? Colors.white70 : Colors.white38,
                  fontSize: 12,
                ),
                side: const BorderSide(color: Colors.white12),
                onSelected: (_) => _save(seconds),
              ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

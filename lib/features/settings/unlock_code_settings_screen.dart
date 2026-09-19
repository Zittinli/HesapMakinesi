import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/secret_config.dart';
import '../../services/settings_service.dart';

class UnlockCodeSettingsScreen extends StatefulWidget {
  const UnlockCodeSettingsScreen({super.key});

  @override
  State<UnlockCodeSettingsScreen> createState() =>
      _UnlockCodeSettingsScreenState();
}

class _UnlockCodeSettingsScreenState extends State<UnlockCodeSettingsScreen> {
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
        SnackBar(content: Text('Giriş kodu: ${settings.unlockLabel} =')),
      );
    }
  }

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
          'Giriş kodu',
          style: TextStyle(fontWeight: FontWeight.w400),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          const Text(
            'Hesap makinesinden sohbete geçen işlem.',
            style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _numberField(_leftController, 'Sol sayı')),
              const SizedBox(width: 8),
              Expanded(child: _numberField(_rightController, 'Sağ sayı')),
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
            'Şu an: ${_leftController.text.isEmpty ? settings.unlockLeft : _leftController.text} $_operator ${_rightController.text.isEmpty ? settings.unlockRight : _rightController.text} =',
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
              'Varsayılana dön',
              style: TextStyle(color: Colors.white38),
            ),
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

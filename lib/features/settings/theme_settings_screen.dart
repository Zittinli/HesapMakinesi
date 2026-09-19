import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/calculator_palette.dart';
import '../../services/settings_service.dart';

class ThemeSettingsScreen extends StatelessWidget {
  const ThemeSettingsScreen({super.key});

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
          'Tema',
          style: TextStyle(fontWeight: FontWeight.w400),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            'Seçili: ${settings.calculatorSkin.label}',
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 8),
          ...CalculatorSkin.values.map((skin) {
            return ListTile(
              contentPadding: EdgeInsets.zero,
              enabled: skin.available,
              title: Text(
                skin.label,
                style: TextStyle(
                  color: skin.available ? Colors.white70 : Colors.white38,
                ),
              ),
              subtitle: Text(
                skin.available ? 'Kullanılabilir' : 'Yakında eklenecek',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
              trailing: Radio<CalculatorSkin>(
                value: skin,
                groupValue: settings.calculatorSkin,
                onChanged: skin.available
                    ? (value) {
                        if (value != null) settings.setCalculatorSkin(value);
                      }
                    : null,
                activeColor: Colors.white70,
              ),
              onTap: skin.available
                  ? () => settings.setCalculatorSkin(skin)
                  : null,
            );
          }),
        ],
      ),
    );
  }
}

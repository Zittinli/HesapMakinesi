import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/calculator_theme.dart';
import '../../services/settings_service.dart';
import 'calculator_controller.dart';

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key, required this.onSecretUnlock});

  final VoidCallback onSecretUnlock;

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  late final CalculatorController _controller;

  static const _buttons = [
    ['C', '±', '%', '÷'],
    ['7', '8', '9', '×'],
    ['4', '5', '6', '-'],
    ['1', '2', '3', '+'],
    ['0', '.', '='],
  ];

  @override
  void initState() {
    super.initState();
    _controller = CalculatorController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handlePress(String label) {
    if (label == '=') {
      SettingsService? settings;
      try {
        settings = Provider.of<SettingsService>(context, listen: false);
      } catch (_) {}
      final unlocked = _controller.onEqualsPressed(
        expectedLeft: settings?.unlockLeft,
        expectedOperator: settings?.unlockOperator,
        expectedRight: settings?.unlockRight,
      );
      if (unlocked) {
        widget.onSecretUnlock();
      }
      return;
    }
    _controller.onButtonPressed(label);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CalculatorTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              flex: 2,
              child: ListenableBuilder(
                listenable: _controller,
                builder: (context, _) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                    alignment: Alignment.bottomRight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (_controller.expressionDisplay !=
                              _controller.display)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                _controller.expressionDisplay,
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  color: CalculatorTheme.displayText
                                      .withValues(alpha: 0.5),
                                  fontSize: 28,
                                  fontWeight: FontWeight.w300,
                                ),
                              ),
                            ),
                          Text(
                            _controller.display,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              color: CalculatorTheme.displayText,
                              fontSize: 72,
                              fontWeight: FontWeight.w300,
                              height: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: _buttons.map((row) {
                    return Expanded(
                      child: Row(
                        children: _buildRow(row),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildRow(List<String> labels) {
    return [
      for (final label in labels)
        Expanded(
          flex: label == '0' ? 2 : 1,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: _CalcButton(
              label: label,
              onPressed: () => _handlePress(label),
            ),
          ),
        ),
    ];
  }
}

class _CalcButton extends StatelessWidget {
  const _CalcButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isOperator = {'+', '-', '×', '÷', '='}.contains(label);
    final isFunction = {'C', '±', '%'}.contains(label);

    final Color background;
    final Color textColor;

    if (isOperator) {
      background = CalculatorTheme.buttonOrange;
      textColor = CalculatorTheme.buttonOrangeText;
    } else if (isFunction) {
      background = CalculatorTheme.buttonLight;
      textColor = CalculatorTheme.buttonLightText;
    } else {
      background = CalculatorTheme.buttonDark;
      textColor = CalculatorTheme.displayText;
    }

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 32,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

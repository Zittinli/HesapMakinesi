import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/calculator_palette.dart';
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

  static const _portraitButtons = [
    ['C', '⌫', '%', '÷'],
    ['7', '8', '9', '×'],
    ['4', '5', '6', '-'],
    ['1', '2', '3', '+'],
    ['0', '.', '='],
  ];

  static const _landscapeButtons = [
    ['sin', 'cos', 'tan', 'ln', 'C', '±', '%', '÷'],
    ['√', 'x²', 'xʸ', 'log', '7', '8', '9', '×'],
    ['π', 'e', '1/x', 'n!', '4', '5', '6', '-'],
    ['10ˣ', 'eˣ', '|x|', 'Deg', '1', '2', '3', '+'],
    ['⌫', 'x³', '³√', 'Rand', '0', '.', '='],
  ];

  @override
  void initState() {
    super.initState();
    _controller = CalculatorController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final settings = context.read<SettingsService>();
        _controller.loadHistory(settings.calculatorHistory);
      } catch (_) {}
    });
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
        return;
      }
      try {
        context.read<SettingsService>().setCalculatorHistory(_controller.history);
      } catch (_) {}
      return;
    }
    _controller.onButtonPressed(label);
  }

  @override
  Widget build(BuildContext context) {
    SettingsService? settings;
    try {
      settings = context.watch<SettingsService>();
    } catch (_) {}
    final palette = CalculatorPalette.of(
      settings?.calculatorSkin ?? CalculatorSkin.classic,
    );

    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: OrientationBuilder(
          builder: (context, orientation) {
            final landscape = orientation == Orientation.landscape;
            return Column(
              children: [
                ListenableBuilder(
                  listenable: _controller,
                  builder: (context, _) {
                    if (_controller.history.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return SizedBox(
                    height: landscape ? 36 : 48,
                    child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          children: [
                            for (final line in _controller.history.take(12))
                              Padding(
                                padding: const EdgeInsets.only(right: 12, top: 8),
                                child: Text(
                                  line,
                                  style: TextStyle(
                                    color: palette.historyText,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                          ],
                        ),
                    );
                  },
                ),
                Expanded(
                  flex: landscape ? 2 : 2,
                  child: ListenableBuilder(
                    listenable: _controller,
                    builder: (context, _) {
                      return Container(
                        width: double.infinity,
                        padding: EdgeInsets.fromLTRB(
                          landscape ? 16 : 24,
                          landscape ? 8 : 16,
                          landscape ? 16 : 24,
                          landscape ? 8 : 16,
                        ),
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
                                  padding: EdgeInsets.only(
                                    bottom: landscape ? 4 : 8,
                                  ),
                                  child: Text(
                                    _controller.expressionDisplay,
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      color: palette.displayText
                                          .withValues(alpha: 0.5),
                                      fontSize: landscape ? 18 : 28,
                                      fontWeight: FontWeight.w300,
                                    ),
                                  ),
                                ),
                              Text(
                                _controller.display,
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  color: palette.displayText,
                                  fontSize: landscape ? 42 : 72,
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
                  flex: landscape ? 5 : 4,
                  child: Padding(
                    padding: EdgeInsets.all(landscape ? 6 : 12),
                    child: ListenableBuilder(
                      listenable: _controller,
                      builder: (context, _) {
                        final rows =
                            landscape ? _landscapeButtons : _portraitButtons;
                        return Column(
                          children: [
                            for (final row in rows)
                              Expanded(
                                child: Row(
                                  children: _buildRow(
                                  row,
                                  compact: landscape,
                                  palette: palette,
                                ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _buildRow(
    List<String> labels, {
    required bool compact,
    required CalculatorPalette palette,
  }) {
    return [
      for (final label in labels)
        Expanded(
          flex: !compact && label == '0' ? 2 : 1,
          child: Padding(
            padding: EdgeInsets.all(compact ? 3 : 6),
            child: _CalcButton(
              label: label == 'Deg'
                  ? (_controller.useDegrees ? 'Deg' : 'Rad')
                  : label,
              compact: compact,
              palette: palette,
              onPressed: () => _handlePress(label == 'Rad' ? 'Deg' : label),
            ),
          ),
        ),
    ];
  }
}

class _CalcButton extends StatelessWidget {
  const _CalcButton({
    required this.label,
    required this.onPressed,
    required this.palette,
    this.compact = false,
  });

  final String label;
  final VoidCallback onPressed;
  final CalculatorPalette palette;
  final bool compact;

  static const _operators = {'+', '-', '×', '÷', '=', 'xʸ'};
  static const _functions = {'C', '⌫', '±', '%', 'Deg', 'Rad'};

  @override
  Widget build(BuildContext context) {
    final isOperator = _operators.contains(label);
    final isFunction = _functions.contains(label);

    final Color background;
    final Color textColor;

    if (isOperator) {
      background = palette.buttonOrange;
      textColor = palette.buttonOrangeText;
    } else if (isFunction) {
      background = palette.buttonLight;
      textColor = palette.buttonLightText;
    } else {
      background = palette.buttonDark;
      textColor = palette.displayText;
    }

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = constraints.maxWidth < constraints.maxHeight
                ? constraints.maxWidth
                : constraints.maxHeight;
            final fontSize = (side * (compact ? 0.34 : 0.38)).clamp(
              11.0,
              compact ? 18.0 : 32.0,
            );
            final iconSize = (side * 0.36).clamp(14.0, compact ? 20.0 : 28.0);

            return Center(
              child: label == '⌫'
                  ? Icon(
                      Icons.backspace_outlined,
                      color: textColor,
                      size: iconSize,
                    )
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        label,
                        style: TextStyle(
                          color: textColor,
                          fontSize: fontSize,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
            );
          },
        ),
      ),
    );
  }
}

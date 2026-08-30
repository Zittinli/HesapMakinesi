import 'package:flutter/foundation.dart';

import '../../core/secret_config.dart';

enum CalculatorButtonType { number, operator, function, equals }

class CalculatorButton {
  const CalculatorButton({
    required this.label,
    required this.type,
    this.spanTwo = false,
  });

  final String label;
  final CalculatorButtonType type;
  final bool spanTwo;
}

class CalculatorController extends ChangeNotifier {
  String _display = '0';
  String? _storedValue;
  String? _pendingOperator;
  bool _waitingForOperand = false;

  String get display => _display;

  /// Ekranda gorunen ifade: ornegin `12 +` veya `12 + 5`.
  String get expressionDisplay {
    if (_pendingOperator != null && _storedValue != null) {
      if (_waitingForOperand) {
        return '$_storedValue $_pendingOperator';
      }
      return '$_storedValue $_pendingOperator $_display';
    }
    return _display;
  }

  void onButtonPressed(String label) {
    switch (label) {
      case 'C':
        _clear();
      case '±':
        _toggleSign();
      case '%':
        _applyPercent();
      case '.':
        _inputDecimal();
      case '+':
      case '-':
      case '×':
      case '÷':
        _inputOperator(label);
      case '=':
        return;
      default:
        _inputDigit(label);
    }
    notifyListeners();
  }

  bool onEqualsPressed({
    String? expectedLeft,
    String? expectedOperator,
    String? expectedRight,
  }) {
    if (SecretConfig.shouldUnlockOperation(
      left: _storedValue,
      operator: _pendingOperator,
      right: _display,
      expectedLeft: expectedLeft,
      expectedOperator: expectedOperator,
      expectedRight: expectedRight,
    )) {
      _clear();
      notifyListeners();
      return true;
    }

    _calculate();
    notifyListeners();
    return false;
  }

  void _clear() {
    _display = '0';
    _storedValue = null;
    _pendingOperator = null;
    _waitingForOperand = false;
  }

  void _toggleSign() {
    if (_display == '0') return;
    if (_display.startsWith('-')) {
      _display = _display.substring(1);
    } else {
      _display = '-$_display';
    }
  }

  void _applyPercent() {
    final value = double.tryParse(_display);
    if (value == null) return;
    _display = _formatResult(value / 100);
    _waitingForOperand = true;
  }

  void _inputDecimal() {
    if (_waitingForOperand) {
      _display = '0.';
      _waitingForOperand = false;
      return;
    }
    if (!_display.contains('.')) {
      _display = '$_display.';
    }
  }

  void _inputDigit(String digit) {
    if (_waitingForOperand || _display == '0') {
      _display = digit;
      _waitingForOperand = false;
    } else if (_display.length < 12) {
      _display = '$_display$digit';
    }
  }

  void _inputOperator(String operator) {
    if (_storedValue != null &&
        _pendingOperator != null &&
        !_waitingForOperand) {
      _calculate();
    }

    _storedValue = _display;
    _pendingOperator = operator;
    _waitingForOperand = true;
  }

  void _calculate() {
    final first = double.tryParse(_storedValue ?? '');
    final second = double.tryParse(_display);
    if (first == null || second == null || _pendingOperator == null) {
      return;
    }

    double result;
    switch (_pendingOperator) {
      case '+':
        result = first + second;
      case '-':
        result = first - second;
      case '×':
        result = first * second;
      case '÷':
        if (second == 0) {
          _display = 'Hata';
          _storedValue = null;
          _pendingOperator = null;
          _waitingForOperand = true;
          return;
        }
        result = first / second;
      default:
        return;
    }

    _display = _formatResult(result);
    _storedValue = null;
    _pendingOperator = null;
    _waitingForOperand = true;
  }

  String _formatResult(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    final text = value.toStringAsFixed(6);
    return text.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }
}

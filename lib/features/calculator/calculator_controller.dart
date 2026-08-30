import 'dart:math' as math;

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
  bool _useDegrees = true;

  String get display => _display;
  bool get useDegrees => _useDegrees;

  /// Ekranda gorunen ifade: ornegin `12 +` veya `12 + 5`.
  String get expressionDisplay {
    if (_pendingOperator != null && _storedValue != null) {
      final symbol = _pendingOperator == '^' ? 'xʸ' : _pendingOperator;
      if (_waitingForOperand) {
        return '$_storedValue $symbol';
      }
      return '$_storedValue $symbol $_display';
    }
    return _display;
  }

  void onButtonPressed(String label) {
    switch (label) {
      case 'C':
        _clear();
      case '⌫':
        _backspace();
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
      case 'xʸ':
        _inputOperator(label == 'xʸ' ? '^' : label);
      case 'sin':
        _applyUnary((value) => math.sin(_toRadians(value)));
      case 'cos':
        _applyUnary((value) => math.cos(_toRadians(value)));
      case 'tan':
        _applyUnary((value) => math.tan(_toRadians(value)));
      case 'ln':
        _applyUnary((value) => value <= 0 ? double.nan : math.log(value));
      case 'log':
        _applyUnary(
          (value) => value <= 0 ? double.nan : math.log(value) / math.ln10,
        );
      case '√':
        _applyUnary((value) => value < 0 ? double.nan : math.sqrt(value));
      case '³√':
        _applyUnary((value) => value < 0
            ? -math.pow(-value, 1 / 3).toDouble()
            : math.pow(value, 1 / 3).toDouble());
      case 'x²':
        _applyUnary((value) => value * value);
      case 'x³':
        _applyUnary((value) => value * value * value);
      case '1/x':
        _applyUnary((value) => value == 0 ? double.nan : 1 / value);
      case '|x|':
        _applyUnary((value) => value.abs());
      case '10ˣ':
        _applyUnary((value) => math.pow(10, value).toDouble());
      case 'eˣ':
        _applyUnary(math.exp);
      case 'n!':
        _applyFactorial();
      case 'π':
        _setConstant(_formatResult(math.pi));
      case 'e':
        _setConstant(_formatResult(math.e));
      case 'Rand':
        _setConstant(_formatResult(math.Random().nextDouble()));
      case 'Deg':
      case 'Rad':
        _useDegrees = !_useDegrees;
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
    final unlocked = SecretConfig.shouldUnlockOperation(
      left: _storedValue,
      operator: _pendingOperator,
      right: _display,
      expectedLeft: expectedLeft,
      expectedOperator: expectedOperator,
      expectedRight: expectedRight,
    );
    debugPrint(
      'HM_UNLOCK ${_storedValue ?? '-'} ${_pendingOperator ?? '-'} $_display '
      'expect ${expectedLeft ?? SecretConfig.secretLeft} '
      '${expectedOperator ?? SecretConfig.secretOperator} '
      '${expectedRight ?? SecretConfig.secretRight} -> $unlocked',
    );
    if (unlocked) {
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

  void _backspace() {
    if (_display == 'Hata') {
      _clear();
      return;
    }

    if (_waitingForOperand && _pendingOperator != null) {
      _display = _storedValue ?? _display;
      _storedValue = null;
      _pendingOperator = null;
      _waitingForOperand = false;
      return;
    }

    _waitingForOperand = false;
    if (_display.length <= 1 ||
        (_display.startsWith('-') && _display.length == 2)) {
      _display = '0';
      return;
    }

    var next = _display.substring(0, _display.length - 1);
    if (next.isEmpty || next == '-') {
      next = '0';
    }
    _display = next;
  }

  void _toggleSign() {
    if (_display == '0' || _display == 'Hata') return;
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

  void _applyUnary(double Function(double value) fn) {
    if (_display == 'Hata') return;
    final value = double.tryParse(_display);
    if (value == null) {
      _display = 'Hata';
      _waitingForOperand = true;
      return;
    }
    final result = fn(value);
    if (result.isNaN || result.isInfinite) {
      _display = 'Hata';
    } else {
      _display = _formatResult(result);
    }
    _waitingForOperand = true;
  }

  void _applyFactorial() {
    final value = double.tryParse(_display);
    if (value == null ||
        value < 0 ||
        value != value.roundToDouble() ||
        value > 170) {
      _display = 'Hata';
      _waitingForOperand = true;
      return;
    }
    var result = 1.0;
    for (var i = 2; i <= value.round(); i++) {
      result *= i;
    }
    _display = _formatResult(result);
    _waitingForOperand = true;
  }

  void _setConstant(String value) {
    _display = value;
    _waitingForOperand = true;
  }

  double _toRadians(double value) {
    return _useDegrees ? value * math.pi / 180 : value;
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
          _setError();
          return;
        }
        result = first / second;
      case '^':
        result = math.pow(first, second).toDouble();
      default:
        return;
    }

    if (result.isNaN || result.isInfinite) {
      _setError();
      return;
    }

    _display = _formatResult(result);
    _storedValue = null;
    _pendingOperator = null;
    _waitingForOperand = true;
  }

  void _setError() {
    _display = 'Hata';
    _storedValue = null;
    _pendingOperator = null;
    _waitingForOperand = true;
  }

  String _formatResult(double value) {
    if (!value.isFinite) return 'Hata';
    if ((value - value.roundToDouble()).abs() < 1e-10 && value.abs() < 1e15) {
      return value.round().toString();
    }
    if (value.abs() >= 1e10 || (value.abs() > 0 && value.abs() < 1e-6)) {
      return value
          .toStringAsExponential(6)
          .replaceAll(RegExp(r'0+e'), 'e')
          .replaceAll(RegExp(r'\.e'), 'e');
    }
    final text = value.toStringAsFixed(8);
    return text.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }
}

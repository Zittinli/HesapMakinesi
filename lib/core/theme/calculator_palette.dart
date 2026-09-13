import 'package:flutter/material.dart';

enum CalculatorSkin { classic, samsung, huawei, xiaomi, iphone }

extension CalculatorSkinX on CalculatorSkin {
  String get id => name;

  String get label {
    switch (this) {
      case CalculatorSkin.classic:
        return 'Klasik';
      case CalculatorSkin.samsung:
        return 'Samsung';
      case CalculatorSkin.huawei:
        return 'Huawei';
      case CalculatorSkin.xiaomi:
        return 'Xiaomi';
      case CalculatorSkin.iphone:
        return 'iPhone';
    }
  }

  bool get available =>
      this == CalculatorSkin.classic || this == CalculatorSkin.samsung;

  static CalculatorSkin fromId(String? id) {
    return CalculatorSkin.values.firstWhere(
      (item) => item.name == id,
      orElse: () => CalculatorSkin.classic,
    );
  }
}

class CalculatorPalette {
  const CalculatorPalette({
    required this.background,
    required this.displayText,
    required this.buttonDark,
    required this.buttonLight,
    required this.buttonLightText,
    required this.buttonOrange,
    required this.buttonOrangeText,
    required this.historyText,
  });

  final Color background;
  final Color displayText;
  final Color buttonDark;
  final Color buttonLight;
  final Color buttonLightText;
  final Color buttonOrange;
  final Color buttonOrangeText;
  final Color historyText;

  static const classic = CalculatorPalette(
    background: Color(0xFF000000),
    displayText: Color(0xFFFFFFFF),
    buttonDark: Color(0xFF333333),
    buttonLight: Color(0xFFA5A5A5),
    buttonLightText: Color(0xFF000000),
    buttonOrange: Color(0xFFFF9500),
    buttonOrangeText: Color(0xFFFFFFFF),
    historyText: Color(0x99FFFFFF),
  );

  static const samsung = CalculatorPalette(
    background: Color(0xFF010101),
    displayText: Color(0xFFF5F5F5),
    buttonDark: Color(0xFF171719),
    buttonLight: Color(0xFF29292B),
    buttonLightText: Color(0xFFF2F2F2),
    buttonOrange: Color(0xFF16A093),
    buttonOrangeText: Color(0xFFFFFFFF),
    historyText: Color(0xFF15988D),
  );

  static CalculatorPalette of(CalculatorSkin skin) {
    switch (skin) {
      case CalculatorSkin.samsung:
        return samsung;
      case CalculatorSkin.classic:
      case CalculatorSkin.huawei:
      case CalculatorSkin.xiaomi:
      case CalculatorSkin.iphone:
        return classic;
    }
  }
}

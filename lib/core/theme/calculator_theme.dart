import 'package:flutter/material.dart';

class CalculatorTheme {
  CalculatorTheme._();

  static const Color background = Color(0xFF000000);
  static const Color displayText = Color(0xFFFFFFFF);
  static const Color buttonDark = Color(0xFF333333);
  static const Color buttonLight = Color(0xFFA5A5A5);
  static const Color buttonLightText = Color(0xFF000000);
  static const Color buttonOrange = Color(0xFFFF9500);
  static const Color buttonOrangeText = Color(0xFFFFFFFF);

  static ThemeData get theme => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        useMaterial3: true,
      );
}

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
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFF161616),
          elevation: 0,
          contentTextStyle: TextStyle(
            color: Colors.white70,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            height: 1.3,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            side: BorderSide(color: Color(0xFF2C2C2C)),
          ),
          insetPadding: EdgeInsets.fromLTRB(12, 8, 12, 16),
        ),
      );
}

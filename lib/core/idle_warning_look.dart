import 'package:flutter/material.dart';

class IdleWarningLook {
  IdleWarningLook._();

  static const window = Duration(seconds: 15);
  static const _resting = Color(0xFF0B0B0B);

  static double progress(DateTime? deadline) {
    if (deadline == null) return 0;
    final left = deadline.difference(DateTime.now());
    if (left >= window) return 0;
    if (left <= Duration.zero) return 1;
    return (1 - left.inMilliseconds / window.inMilliseconds).clamp(0.0, 1.0);
  }

  static double ease(double progress) =>
      Curves.easeInCubic.transform(progress.clamp(0.0, 1.0));

  static Color scaffold(double progress) {
    return Color.lerp(_resting, const Color(0xFF1C0A10), ease(progress))!;
  }

  static Color appBar(double progress) {
    return Color.lerp(_resting, const Color(0xFF4A1520), ease(progress))!;
  }

  static Color nameWash(double progress) {
    return Color.lerp(Colors.transparent, const Color(0x8A5C1A28), ease(progress))!;
  }

  static Color overlayInner(double progress) {
    return Color.lerp(const Color(0x00000000), const Color(0x335C1A28), ease(progress))!;
  }

  static Color overlayEdge(double progress) {
    return Color.lerp(const Color(0x00000000), const Color(0x8F5C1A28), ease(progress))!;
  }
}

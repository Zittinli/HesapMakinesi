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
      Curves.easeInOutCubic.transform(progress.clamp(0.0, 1.0));

  static Color scaffold(double progress) {
    return Color.lerp(_resting, const Color(0xFF161018), ease(progress))!;
  }

  static Color appBar(double progress) {
    return Color.lerp(_resting, const Color(0xFF2A1822), ease(progress))!;
  }

  static Color nameWash(double progress) {
    return Color.lerp(
      Colors.transparent,
      const Color(0x664E2A38),
      ease(progress),
    )!;
  }

  static Color overlayInner(double progress) {
    return Color.lerp(
      const Color(0x00000000),
      const Color(0x334E2A38),
      ease(progress),
    )!;
  }

  static Color overlayEdge(double progress) {
    return Color.lerp(
      const Color(0x00000000),
      const Color(0x735C2438),
      ease(progress),
    )!;
  }
}

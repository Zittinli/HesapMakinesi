import 'package:flutter/services.dart';

class NudgeHaptic {
  NudgeHaptic._();

  static const _channel = MethodChannel(
    'com.hesapmakinesi.hesap_makinesi/nudge',
  );
  static DateTime? _lastPlay;

  static bool isFresh(DateTime? sentAt) {
    if (sentAt == null) return true;
    return DateTime.now().difference(sentAt) <= const Duration(seconds: 8);
  }

  static Future<bool> isBatteryUnrestricted() async {
    try {
      final value = await _channel.invokeMethod<bool>('batteryUnrestricted');
      return value == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> requestBatteryUnrestricted() async {
    try {
      await _channel.invokeMethod<void>('requestBatteryUnrestricted');
    } catch (_) {}
  }

  static Future<void> play() async {
    final now = DateTime.now();
    if (_lastPlay != null &&
        now.difference(_lastPlay!) < const Duration(milliseconds: 550)) {
      return;
    }
    _lastPlay = now;
    try {
      await _channel.invokeMethod<void>('play');
    } on MissingPluginException {
      await _fallback();
    } on PlatformException {
      await _fallback();
    }
  }

  static Future<void> _fallback() async {
    await HapticFeedback.lightImpact();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await HapticFeedback.lightImpact();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await HapticFeedback.lightImpact();
    await Future<void>.delayed(const Duration(milliseconds: 70));
    await HapticFeedback.lightImpact();
    await Future<void>.delayed(const Duration(milliseconds: 70));
    await HapticFeedback.lightImpact();
    await Future<void>.delayed(const Duration(milliseconds: 70));
    await HapticFeedback.lightImpact();
  }
}

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/secret_config.dart';
import '../core/theme/calculator_palette.dart';
import '../models/notification_look.dart';

class SettingsService extends ChangeNotifier {
  SettingsService();

  static const _keyLeft = 'unlock_left';
  static const _keyOperator = 'unlock_operator';
  static const _keyRight = 'unlock_right';
  static const _keyLook = 'notification_look';
  static const _keySound = 'notification_sound';
  static const _keyVibrate = 'notification_vibrate';
  static const _keyTyping = 'privacy_typing';
  static const _keyReadReceipts = 'privacy_read_receipts';
  static const _keyLastSeen = 'privacy_last_seen';
  static const _keyTheme = 'calculator_theme';
  static const _keyHistory = 'calculator_history';

  static const allowedOperators = ['×', '+', '-', '÷'];

  String _unlockLeft = SecretConfig.secretLeft;
  String _unlockOperator = SecretConfig.secretOperator;
  String _unlockRight = SecretConfig.secretRight;
  NotificationLook _notificationLook = NotificationLook.cover;
  bool _sound = false;
  bool _vibrate = false;
  bool _typingEnabled = true;
  bool _readReceiptsEnabled = true;
  bool _lastSeenEnabled = true;
  CalculatorSkin _calculatorSkin = CalculatorSkin.classic;
  List<String> _calculatorHistory = [];
  bool _ready = false;

  String get unlockLeft => _unlockLeft;
  String get unlockOperator => _unlockOperator;
  String get unlockRight => _unlockRight;
  String get unlockLabel => '$_unlockLeft $_unlockOperator $_unlockRight';
  NotificationLook get notificationLook => _notificationLook;
  bool get soundEnabled => _sound;
  bool get vibrateEnabled => _vibrate;
  bool get typingEnabled => _typingEnabled;
  bool get readReceiptsEnabled => _readReceiptsEnabled;
  bool get lastSeenEnabled => _lastSeenEnabled;
  CalculatorSkin get calculatorSkin => _calculatorSkin;
  List<String> get calculatorHistory => List.unmodifiable(_calculatorHistory);
  bool get ready => _ready;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _unlockLeft = prefs.getString(_keyLeft) ?? SecretConfig.secretLeft;
    _unlockOperator = prefs.getString(_keyOperator) ?? SecretConfig.secretOperator;
    _unlockRight = prefs.getString(_keyRight) ?? SecretConfig.secretRight;
    if (!allowedOperators.contains(_unlockOperator)) {
      _unlockOperator = SecretConfig.secretOperator;
    }
    _notificationLook = NotificationLook.values.firstWhere(
      (item) => item.name == prefs.getString(_keyLook),
      orElse: () => NotificationLook.cover,
    );
    _sound = prefs.getBool(_keySound) ?? false;
    _vibrate = prefs.getBool(_keyVibrate) ?? false;
    _typingEnabled = prefs.getBool(_keyTyping) ?? true;
    _readReceiptsEnabled = prefs.getBool(_keyReadReceipts) ?? true;
    _lastSeenEnabled = prefs.getBool(_keyLastSeen) ?? true;
    _calculatorSkin = CalculatorSkinX.fromId(prefs.getString(_keyTheme));
    _calculatorHistory = prefs.getStringList(_keyHistory) ?? [];
    _ready = true;
    notifyListeners();
  }

  Future<String?> setUnlockCode({
    required String left,
    required String operator,
    required String right,
  }) async {
    final cleanLeft = left.replaceAll(RegExp(r'[^0-9]'), '');
    final cleanRight = right.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanLeft.isEmpty || cleanRight.isEmpty) {
      return 'Her iki sayi da gerekli.';
    }
    if (cleanLeft.length > 12 || cleanRight.length > 12) {
      return 'Sayilar en fazla 12 haneli olabilir.';
    }
    if (!allowedOperators.contains(operator)) {
      return 'Gecersiz islem.';
    }

    _unlockLeft = cleanLeft;
    _unlockOperator = operator;
    _unlockRight = cleanRight;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLeft, _unlockLeft);
    await prefs.setString(_keyOperator, _unlockOperator);
    await prefs.setString(_keyRight, _unlockRight);
    notifyListeners();
    return null;
  }

  Future<void> setNotificationLook(NotificationLook look) async {
    _notificationLook = look;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLook, look.name);
    notifyListeners();
  }

  Future<void> setSoundEnabled(bool value) async {
    _sound = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySound, value);
    notifyListeners();
  }

  Future<void> setVibrateEnabled(bool value) async {
    _vibrate = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyVibrate, value);
    notifyListeners();
  }

  Future<void> setTypingEnabled(bool value) async {
    _typingEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyTyping, value);
    notifyListeners();
  }

  Future<void> setReadReceiptsEnabled(bool value) async {
    _readReceiptsEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyReadReceipts, value);
    notifyListeners();
  }

  Future<void> setCalculatorSkin(CalculatorSkin skin) async {
    if (!skin.available) return;
    _calculatorSkin = skin;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTheme, skin.id);
    notifyListeners();
  }

  Future<void> setCalculatorHistory(List<String> items) async {
    _calculatorHistory = items.take(50).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyHistory, _calculatorHistory);
    notifyListeners();
  }

  Future<void> setLastSeenEnabled(bool value) async {
    _lastSeenEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyLastSeen, value);
    notifyListeners();
  }
}

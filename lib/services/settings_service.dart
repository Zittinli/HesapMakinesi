import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/emoji_catalog.dart';
import '../core/secret_config.dart';
import '../core/theme/calculator_palette.dart';
import '../models/notification_look.dart';

class SettingsService extends ChangeNotifier {
  SettingsService();

  static const _launcherIconChannel = MethodChannel(
    'com.hesapmakinesi.hesap_makinesi/launcher_icon',
  );
  static const _screenSecurityChannel = MethodChannel(
    'com.hesapmakinesi.hesap_makinesi/screen_security',
  );
  static const _keyLeft = 'unlock_left';
  static const _keyOperator = 'unlock_operator';
  static const _keyRight = 'unlock_right';
  static const _keyLook = 'notification_look';
  static const _keySound = 'notification_sound';
  static const _keyVibrate = 'notification_vibrate';
  static const _keyTyping = 'privacy_typing';
  static const _keyReadReceipts = 'privacy_read_receipts';
  static const _keyLastSeen = 'privacy_last_seen';
  static const _keyScreenProtection = 'privacy_screen_protection';
  static const _keyTheme = 'calculator_theme';
  static const _keyHistory = 'calculator_history';
  static const _keyIdleSeconds = 'chat_idle_seconds';
  static const _keySkipCalculator = 'privacy_skip_calculator';
  static const _keyFavoriteEmojis = 'chat_favorite_emojis';
  static const _keyDownloadedMedia = 'chat_downloaded_media';
  static const _keyUploadedMedia = 'chat_uploaded_media';
  static const _keyMediaFiles = 'chat_media_files_v1';
  static const defaultFavoriteEmojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

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
  bool _screenProtectionEnabled = false;
  CalculatorSkin _calculatorSkin = CalculatorSkin.samsung;
  int _chatIdleSeconds = 150;
  bool _skipCalculator = false;
  List<String> _calculatorHistory = [];
  List<String> _favoriteEmojis = List<String>.from(defaultFavoriteEmojis);
  bool _preferLocalQuickEmojis = false;
  final Set<String> _downloadedMediaIds = {};
  final Set<String> _uploadedMediaIds = {};
  final Map<String, String> _mediaFiles = {};
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
  bool get screenProtectionEnabled => _screenProtectionEnabled;
  CalculatorSkin get calculatorSkin => _calculatorSkin;
  int get chatIdleSeconds => _chatIdleSeconds;
  bool get skipCalculator => _skipCalculator;
  bool get showIdleCountdown => false;
  List<String> get calculatorHistory => List.unmodifiable(_calculatorHistory);
  List<String> get favoriteEmojis => List.unmodifiable(_favoriteEmojis);
  bool get ready => _ready;

  bool isMediaDownloaded(String messageId) =>
      messageId.isNotEmpty && _downloadedMediaIds.contains(messageId);

  bool isMediaUploaded(String messageId) =>
      messageId.isNotEmpty && _uploadedMediaIds.contains(messageId);

  String? mediaFilePath(String key) {
    if (key.isEmpty) return null;
    final path = _mediaFiles[key];
    if (path == null || path.isEmpty) return null;
    return path;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _unlockLeft = prefs.getString(_keyLeft) ?? SecretConfig.secretLeft;
    _unlockOperator =
        prefs.getString(_keyOperator) ?? SecretConfig.secretOperator;
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
    _screenProtectionEnabled = prefs.getBool(_keyScreenProtection) ?? false;
    _calculatorSkin = CalculatorSkinX.fromId(
      prefs.getString(_keyTheme) ?? CalculatorSkin.samsung.id,
    );
    _chatIdleSeconds = prefs.getInt(_keyIdleSeconds) ?? 150;
    if (_chatIdleSeconds < 30) _chatIdleSeconds = 30;
    if (_chatIdleSeconds > 1800) _chatIdleSeconds = 1800;
    _skipCalculator = prefs.getBool(_keySkipCalculator) ?? false;
    _calculatorHistory = prefs.getStringList(_keyHistory) ?? [];
    final savedEmojis = prefs.getStringList(_keyFavoriteEmojis);
    final cleaned = EmojiCatalog.normalize(savedEmojis ?? const []);
    _favoriteEmojis = cleaned.isEmpty
        ? List<String>.from(defaultFavoriteEmojis)
        : cleaned;
    _downloadedMediaIds
      ..clear()
      ..addAll(prefs.getStringList(_keyDownloadedMedia) ?? const []);
    _uploadedMediaIds
      ..clear()
      ..addAll(prefs.getStringList(_keyUploadedMedia) ?? const []);
    _mediaFiles
      ..clear()
      ..addAll(_readMediaFiles(prefs.getString(_keyMediaFiles)));
    await _syncScreenProtection();
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
      return 'Her iki sayı da gerekli.';
    }
    if (cleanLeft.length > 12 || cleanRight.length > 12) {
      return 'Sayılar en fazla 12 haneli olabilir.';
    }
    if (!allowedOperators.contains(operator)) {
      return 'Geçersiz işlem.';
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

  Future<void> setChatIdleSeconds(int seconds) async {
    _chatIdleSeconds = seconds.clamp(30, 1800);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyIdleSeconds, _chatIdleSeconds);
    notifyListeners();
  }

  Future<void> setCalculatorSkin(CalculatorSkin skin) async {
    if (!skin.available) return;
    _calculatorSkin = skin;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTheme, skin.id);
    await _syncLauncherIcon();
    notifyListeners();
  }

  Future<void> _syncLauncherIcon() async {
    try {
      await _launcherIconChannel.invokeMethod<void>('setLauncherIcon', {
        'samsung': _calculatorSkin == CalculatorSkin.samsung,
      });
    } on MissingPluginException {
      // Android disindaki platformlarda varsayilan ikon kullanilir.
    } on PlatformException {
      // Launcher degisikligi desteklenmiyorsa tema yine uygulanir.
    }
  }

  Future<void> setCalculatorHistory(List<String> items) async {
    _calculatorHistory = items.take(50).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyHistory, _calculatorHistory);
    notifyListeners();
  }

  Future<void> setFavoriteEmojis(List<String> emojis) async {
    final cleaned = EmojiCatalog.normalize(emojis);
    _favoriteEmojis = cleaned.isEmpty
        ? List<String>.from(defaultFavoriteEmojis)
        : cleaned;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyFavoriteEmojis, _favoriteEmojis);
    notifyListeners();
  }

  void keepLocalQuickEmojis() {
    _preferLocalQuickEmojis = true;
  }

  void applyFavoriteEmojis(List<String> emojis) {
    final cleaned = EmojiCatalog.normalize(emojis);
    if (cleaned.isEmpty) return;
    if (_preferLocalQuickEmojis) {
      if (listEquals(cleaned, _favoriteEmojis)) {
        _preferLocalQuickEmojis = false;
      }
      return;
    }
    if (listEquals(cleaned, _favoriteEmojis)) return;
    _favoriteEmojis = cleaned;
    notifyListeners();
    unawaited(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_keyFavoriteEmojis, _favoriteEmojis);
    }());
  }

  Future<void> markMediaDownloaded(String messageId) async {
    if (messageId.isEmpty || !_downloadedMediaIds.add(messageId)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _keyDownloadedMedia,
      _downloadedMediaIds.toList(),
    );
    notifyListeners();
  }

  Future<void> rememberMediaFile(Iterable<String> keys, String path) async {
    if (path.isEmpty) return;
    var changed = false;
    for (final key in keys) {
      if (key.isEmpty) continue;
      if (_mediaFiles[key] == path) continue;
      _mediaFiles[key] = path;
      changed = true;
    }
    if (!changed) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMediaFiles, jsonEncode(_mediaFiles));
    notifyListeners();
  }

  Map<String, String> _readMediaFiles(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> markMediaUploaded(Iterable<String> messageIds) async {
    var changed = false;
    for (final id in messageIds) {
      if (id.isEmpty) continue;
      if (_uploadedMediaIds.add(id)) changed = true;
    }
    if (!changed) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyUploadedMedia, _uploadedMediaIds.toList());
    notifyListeners();
  }

  Future<void> toggleFavoriteEmoji(String emoji) async {
    final next = [..._favoriteEmojis];
    if (next.contains(emoji)) {
      next.remove(emoji);
    } else if (next.length < 8) {
      next.add(emoji);
    }
    await setFavoriteEmojis(next);
  }

  Future<void> setSkipCalculator(bool value) async {
    _skipCalculator = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySkipCalculator, value);
    notifyListeners();
  }

  Future<void> setLastSeenEnabled(bool value) async {
    _lastSeenEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyLastSeen, value);
    notifyListeners();
  }

  Future<void> setScreenProtectionEnabled(bool value) async {
    _screenProtectionEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyScreenProtection, value);
    await _syncScreenProtection();
    notifyListeners();
  }

  Future<void> _syncScreenProtection() async {
    try {
      await _screenSecurityChannel.invokeMethod<void>('setScreenProtection', {
        'enabled': _screenProtectionEnabled,
      });
    } on MissingPluginException {
      // Android disindaki platformlarda yerel ekran korumasi kullanilmaz.
    } on PlatformException {
      // Cihaz desteklemiyorsa ayar kayitli kalir.
    }
  }
}

import 'package:intl/intl.dart';

class ChatFormat {
  static const presenceHeartbeat = Duration(seconds: 20);
  static const presenceFreshFor = Duration(seconds: 120);
  static const turkeyOffset = Duration(hours: 3);

  /// Türkiye duvar saati. Cihaz Avrupa yaz saatinde (UTC+2) olsa da UTC+3 basar.
  static DateTime turkeyClock(DateTime time) {
    final shifted = time.toUtc().add(turkeyOffset);
    return DateTime(
      shifted.year,
      shifted.month,
      shifted.day,
      shifted.hour,
      shifted.minute,
      shifted.second,
      shifted.millisecond,
    );
  }

  static bool isFreshOnline({
    required bool isOnline,
    DateTime? lastSeen,
    DateTime? now,
  }) {
    if (!isOnline || lastSeen == null) return false;
    return (now ?? DateTime.now()).difference(lastSeen) <= presenceFreshFor;
  }

  static String initials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final local = trimmed.contains('@') ? trimmed.split('@').first : trimmed;
    final parts = local.split(RegExp(r'[.\s_]+')).where((p) => p.isNotEmpty);
    if (parts.length >= 2) {
      return (parts.elementAt(0)[0] + parts.elementAt(1)[0]).toUpperCase();
    }
    return local.substring(0, local.length >= 2 ? 2 : 1).toUpperCase();
  }

  static String listTime(DateTime? time) {
    if (time == null) return '';
    final local = turkeyClock(time);
    final now = turkeyClock(DateTime.now());
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return DateFormat('HH:mm').format(local);
    if (diff == 1) return 'Dün ${DateFormat('HH:mm').format(local)}';
    if (local.year == now.year) {
      return DateFormat('dd.MM HH:mm').format(local);
    }
    return DateFormat('dd.MM.yy HH:mm').format(local);
  }

  static String dayLabel(DateTime time) {
    final local = turkeyClock(time);
    final now = turkeyClock(DateTime.now());
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Bugün';
    if (diff == 1) return 'Dün';
    return DateFormat('dd.MM.yyyy').format(local);
  }

  static String messageTime(DateTime? time) {
    if (time == null) return '';
    return DateFormat('HH:mm').format(turkeyClock(time));
  }

  static String eventDateTime(DateTime? time) {
    if (time == null) return '';
    return DateFormat('dd.MM.yyyy HH:mm').format(turkeyClock(time));
  }

  static String lastSeenLabel(
    DateTime? time, {
    DateTime? now,
    bool isOnline = false,
  }) {
    if (isFreshOnline(isOnline: isOnline, lastSeen: time, now: now)) {
      return 'Aktif';
    }
    if (time == null) return '';
    final local = turkeyClock(time);
    final current = turkeyClock(now ?? DateTime.now());
    final minutes = (now ?? DateTime.now()).difference(time).inMinutes;
    if (minutes < 2) return 'Son aktif: az önce';
    final today = DateTime(current.year, current.month, current.day);
    final day = DateTime(local.year, local.month, local.day);
    final diff = today.difference(day).inDays;
    final clock = DateFormat('HH:mm').format(local);
    if (diff == 0) return 'Son görülme: $clock';
    if (diff == 1) return 'Son görülme: Dün $clock';
    if (local.year == current.year) {
      return 'Son görülme: ${DateFormat('dd.MM').format(local)} $clock';
    }
    return 'Son görülme: ${DateFormat('dd.MM.yy').format(local)} $clock';
  }

  static bool isSameDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) return false;
    final left = turkeyClock(a);
    final right = turkeyClock(b);
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }
}

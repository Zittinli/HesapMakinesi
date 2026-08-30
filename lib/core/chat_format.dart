import 'package:intl/intl.dart';

class ChatFormat {
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
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(time.year, time.month, time.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return DateFormat('HH:mm').format(time);
    if (diff == 1) return 'Dün';
    if (time.year == now.year) return DateFormat('dd.MM').format(time);
    return DateFormat('dd.MM.yy').format(time);
  }

  static String dayLabel(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(time.year, time.month, time.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Bugün';
    if (diff == 1) return 'Dün';
    return DateFormat('dd.MM.yyyy').format(time);
  }

  static String messageTime(DateTime? time) {
    if (time == null) return '';
    return DateFormat('HH:mm').format(time);
  }

  static String lastSeenLabel(
    DateTime? time, {
    DateTime? now,
    bool isOnline = false,
  }) {
    if (isOnline) return 'Aktif';
    if (time == null) return '';
    final current = now ?? DateTime.now();
    final minutes = current.difference(time).inMinutes;
    if (minutes < 2) return 'Son aktif: az once';
    final today = DateTime(current.year, current.month, current.day);
    final day = DateTime(time.year, time.month, time.day);
    final diff = today.difference(day).inDays;
    final clock = DateFormat('HH:mm').format(time);
    if (diff == 0) return 'Son gorulme: $clock';
    if (diff == 1) return 'Son gorulme: Dün $clock';
    if (time.year == current.year) {
      return 'Son gorulme: ${DateFormat('dd.MM').format(time)} $clock';
    }
    return 'Son gorulme: ${DateFormat('dd.MM.yy').format(time)} $clock';
  }

  static bool isSameDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

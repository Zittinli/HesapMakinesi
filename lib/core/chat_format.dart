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
    final local = time.toLocal();
    final now = DateTime.now();
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
    final local = time.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Bugün';
    if (diff == 1) return 'Dün';
    return DateFormat('dd.MM.yyyy').format(local);
  }

  static String messageTime(DateTime? time) {
    if (time == null) return '';
    return DateFormat('HH:mm').format(time.toLocal());
  }

  static String eventDateTime(DateTime? time) {
    if (time == null) return '';
    return DateFormat('dd.MM.yyyy HH:mm').format(time.toLocal());
  }

  static String lastSeenLabel(
    DateTime? time, {
    DateTime? now,
    bool isOnline = false,
  }) {
    if (isOnline) return 'Aktif';
    if (time == null) return '';
    final local = time.toLocal();
    final current = now ?? DateTime.now();
    final minutes = current.difference(local).inMinutes;
    if (minutes < 2) return 'Son aktif: az once';
    final today = DateTime(current.year, current.month, current.day);
    final day = DateTime(local.year, local.month, local.day);
    final diff = today.difference(day).inDays;
    final clock = DateFormat('HH:mm').format(local);
    if (diff == 0) return 'Son gorulme: $clock';
    if (diff == 1) return 'Son gorulme: Dün $clock';
    if (local.year == current.year) {
      return 'Son gorulme: ${DateFormat('dd.MM').format(local)} $clock';
    }
    return 'Son gorulme: ${DateFormat('dd.MM.yy').format(local)} $clock';
  }

  static bool isSameDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

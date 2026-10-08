class StaffPerm {
  static const viewReports = 'viewReports';
  static const punishReports = 'punishReports';
  static const readLogs = 'readLogs';
  static const viewUsers = 'viewUsers';
  static const viewGroups = 'viewGroups';
  static const viewGroupMembers = 'viewGroupMembers';
  static const timeoutGroup = 'timeoutGroup';

  static const all = <String>[
    viewReports,
    punishReports,
    readLogs,
    viewUsers,
    viewGroups,
    viewGroupMembers,
    timeoutGroup,
  ];

  static const labels = <String, String>{
    viewReports: 'Mesaj bildirimlerini görmek',
    punishReports: 'Raporlara ceza vermek',
    readLogs: 'Logları okumak',
    viewUsers: 'Kişiler listesini görmek',
    viewGroups: 'Tüm grupları görmek',
    viewGroupMembers: 'Grup üyelerini görmek',
    timeoutGroup: 'Gruba timeout atmak',
  };

  static String labelOf(String perm) => labels[perm] ?? perm;

  static Set<String> normalize(Iterable<String> raw) {
    final next = raw.where(all.contains).toSet();
    if (next.contains(punishReports)) next.add(viewReports);
    if (next.contains(timeoutGroup) || next.contains(viewGroupMembers)) {
      next.add(viewGroups);
    }
    return next;
  }

  static Set<String> toggle(Iterable<String> current, String perm) {
    final next = normalize(current);
    if (next.contains(perm)) {
      next.remove(perm);
      if (perm == viewReports) next.remove(punishReports);
      if (perm == viewGroups) {
        next.remove(viewGroupMembers);
        next.remove(timeoutGroup);
      }
      return normalize(next);
    }
    next.add(perm);
    return normalize(next);
  }

  static bool has(Iterable<String> perms, String perm) =>
      normalize(perms).contains(perm);
}

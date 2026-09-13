import 'package:cloud_firestore/cloud_firestore.dart';

enum ReportReason { spam, abuse, hate, sexual, illegal, other }

extension ReportReasonLabel on ReportReason {
  String get label {
    switch (this) {
      case ReportReason.spam:
        return 'Spam';
      case ReportReason.abuse:
        return 'Taciz / hakaret';
      case ReportReason.hate:
        return 'Nefret soylemi';
      case ReportReason.sexual:
        return 'Cinsel icerik';
      case ReportReason.illegal:
        return 'Yasa disi icerik';
      case ReportReason.other:
        return 'Diger';
    }
  }
}

class MessageReport {
  const MessageReport({
    required this.id,
    required this.reporterId,
    required this.reporterEmail,
    required this.reportedUserId,
    required this.reportedEmail,
    required this.chatId,
    required this.messageId,
    required this.messageText,
    required this.reason,
    required this.status,
    this.createdAt,
    this.action = '',
    this.transcript = '',
    this.history = const [],
    this.isGroup = false,
    this.groupName = '',
  });

  final String id;
  final String reporterId;
  final String reporterEmail;
  final String reportedUserId;
  final String reportedEmail;
  final String chatId;
  final String messageId;
  final String messageText;
  final ReportReason reason;
  final String status;
  final DateTime? createdAt;
  final String action;
  final String transcript;
  final List<Map<String, dynamic>> history;
  final bool isGroup;
  final String groupName;

  factory MessageReport.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    final reasonRaw = data['reason'] as String? ?? 'other';
    return MessageReport(
      id: doc.id,
      reporterId: data['reporterId'] as String? ?? '',
      reporterEmail: data['reporterEmail'] as String? ?? '',
      reportedUserId: data['reportedUserId'] as String? ?? '',
      reportedEmail: data['reportedEmail'] as String? ?? '',
      chatId: data['chatId'] as String? ?? '',
      messageId: data['messageId'] as String? ?? '',
      messageText: data['messageText'] as String? ?? '',
      reason: ReportReason.values.firstWhere(
        (item) => item.name == reasonRaw,
        orElse: () => ReportReason.other,
      ),
      status: data['status'] as String? ?? 'pending',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      action: data['action'] as String? ?? '',
      transcript: data['transcript'] as String? ?? '',
      history: List<Map<String, dynamic>>.from(
        (data['history'] as List? ?? []).whereType<Map>().map(
          (item) => Map<String, dynamic>.from(item),
        ),
      ),
      isGroup: data['isGroup'] as bool? ?? false,
      groupName: data['groupName'] as String? ?? '',
    );
  }
}

class ReportedUserGroup {
  const ReportedUserGroup({
    required this.userId,
    required this.email,
    required this.reports,
  });

  final String userId;
  final String email;
  final List<MessageReport> reports;

  String get title => email.isNotEmpty ? email : userId;

  int get pendingCount =>
      reports.where((item) => item.status == 'pending').length;

  DateTime? get latestAt {
    DateTime? latest;
    for (final report in reports) {
      final time = report.createdAt;
      if (time == null) continue;
      if (latest == null || time.isAfter(latest)) latest = time;
    }
    return latest;
  }
}

List<ReportedUserGroup> groupReportsByUser(List<MessageReport> reports) {
  final map = <String, List<MessageReport>>{};
  for (final report in reports) {
    final key = report.reportedEmail.isNotEmpty
        ? report.reportedEmail
        : (report.reportedUserId.isNotEmpty
              ? report.reportedUserId
              : report.id);
    map.putIfAbsent(key, () => []).add(report);
  }
  final groups = map.entries.map((entry) {
    final items = [...entry.value]
      ..sort(
        (a, b) => (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
      );
    return ReportedUserGroup(
      userId: items.first.reportedUserId,
      email: items.first.reportedEmail,
      reports: items,
    );
  }).toList();
  groups.sort((a, b) {
    if (a.pendingCount != b.pendingCount) {
      return b.pendingCount.compareTo(a.pendingCount);
    }
    return (b.latestAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
      a.latestAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  });
  return groups;
}

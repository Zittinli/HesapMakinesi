import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/chat_format.dart';
import '../../models/report_model.dart';
import '../../services/moderation_service.dart';

class AdminReportsScreen extends StatelessWidget {
  const AdminReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B0B),
        foregroundColor: Colors.white70,
        elevation: 0,
        title: const Text('Bildirilen kullanicilar'),
      ),
      body: const AdminReportsList(),
    );
  }
}

class AdminReportsList extends StatelessWidget {
  const AdminReportsList({super.key});

  @override
  Widget build(BuildContext context) {
    final moderation = context.read<ModerationService>();

    return StreamBuilder<List<MessageReport>>(
      stream: moderation.watchReports(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Raporlar okunamadi. Bu hesap yonetici e-postasi olmali.',
                style: TextStyle(color: Colors.white38),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white24),
          );
        }
        final groups = groupReportsByUser(snapshot.data!);
        if (groups.isEmpty) {
          return const Center(
            child: Text(
              'Henuz bildirim yok.',
              style: TextStyle(color: Colors.white38),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          itemCount: groups.length,
          separatorBuilder: (_, __) => const Divider(color: Color(0xFF222222)),
          itemBuilder: (context, index) {
            return _ReportedUserTile(group: groups[index]);
          },
        );
      },
    );
  }
}

class _ReportedUserTile extends StatelessWidget {
  const _ReportedUserTile({required this.group});

  final ReportedUserGroup group;

  @override
  Widget build(BuildContext context) {
    final pending = group.pendingCount;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        iconColor: Colors.white38,
        collapsedIconColor: Colors.white24,
        title: Text(
          group.title,
          style: const TextStyle(color: Colors.white70, fontSize: 15),
        ),
        subtitle: Text(
          [
            '${group.reports.length} bildirim',
            if (pending > 0) '$pending bekliyor',
            ChatFormat.listTime(group.latestAt),
          ].where((item) => item.isNotEmpty).join(' · '),
          style: TextStyle(
            color: pending > 0 ? const Color(0xFFFFCC80) : Colors.white38,
            fontSize: 12,
          ),
        ),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _userActionChip(context, '1 saat', const Duration(hours: 1)),
              _userActionChip(context, '24 saat', const Duration(hours: 24)),
              _userActionChip(context, '7 gun', const Duration(days: 7)),
              _userActionChip(context, 'Kalici ban', null, permanent: true),
              ActionChip(
                label: const Text('Cezayi kaldir'),
                onPressed: () => _clear(context),
                backgroundColor: const Color(0xFF161616),
                labelStyle: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                ),
              ),
              if (group.reports.any((report) => report.isGroup))
                ActionChip(
                  label: const Text('Tüm gruplardan çıkar'),
                  onPressed: () => _removeFromAllGroups(context),
                  backgroundColor: const Color(0xFF3A1A1A),
                  labelStyle: const TextStyle(
                    color: Color(0xFFFF8A80),
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ...group.reports.map((report) => _ReportTile(report: report)),
        ],
      ),
    );
  }

  Widget _userActionChip(
    BuildContext context,
    String label,
    Duration? timeout, {
    bool permanent = false,
  }) {
    return ActionChip(
      label: Text(label),
      onPressed: () => _penalizeUser(
        context,
        timeout: timeout,
        permanent: permanent,
        action: label,
      ),
      backgroundColor: permanent
          ? const Color(0xFF3A1A1A)
          : const Color(0xFF1A1A1A),
      labelStyle: TextStyle(
        color: permanent ? const Color(0xFFFF8A80) : Colors.white70,
        fontSize: 12,
      ),
    );
  }

  Future<void> _penalizeUser(
    BuildContext context, {
    Duration? timeout,
    bool permanent = false,
    required String action,
  }) async {
    final moderation = context.read<ModerationService>();
    final sample = group.reports.first;
    try {
      await moderation.applyPenalty(
        userId: group.userId,
        email: group.email,
        reason: '${sample.reason.label}: ${sample.messageText}',
        timeout: timeout,
        permanent: permanent,
      );
      for (final report in group.reports.where(
        (item) => item.status == 'pending',
      )) {
        await moderation.markReportReviewed(report.id, action: action);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$action uygulandi.')));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _clear(BuildContext context) async {
    final moderation = context.read<ModerationService>();
    try {
      await moderation.clearPenalty(userId: group.userId, email: group.email);
      for (final report in group.reports.where(
        (item) => item.status == 'pending',
      )) {
        await moderation.markReportReviewed(report.id, action: 'cleared');
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _removeFromAllGroups(BuildContext context) async {
    try {
      final count = await context
          .read<ModerationService>()
          .removeReportedUserFromAllGroups(group.userId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kullanıcı $count gruptan çıkarıldı.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({required this.report});

  final MessageReport report;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                report.reason.label,
                style: const TextStyle(color: Color(0xFFFFCC80), fontSize: 13),
              ),
              const SizedBox(width: 8),
              Text(
                report.status,
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
              const Spacer(),
              Text(
                ChatFormat.listTime(report.createdAt),
                style: const TextStyle(color: Colors.white30, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            report.messageText.isEmpty ? '(bos mesaj)' : report.messageText,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 6),
          Text(
            'Bildiren: ${report.reporterEmail}',
            style: const TextStyle(color: Colors.white30, fontSize: 12),
          ),
          if (report.isGroup)
            Text(
              'Grup: ${report.groupName.isEmpty ? report.chatId : report.groupName}',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          if (report.action.isNotEmpty)
            Text(
              'Islem: ${report.action}',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
          if (report.transcript.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF141414),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                report.transcript,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                label: const Text('Reddet'),
                onPressed: () => _review(context, 'reviewed'),
                backgroundColor: const Color(0xFF161616),
                labelStyle: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                ),
              ),
              if (report.isGroup)
                ActionChip(
                  label: const Text('Bu gruptan çıkar'),
                  onPressed: () => _removeFromGroup(context),
                  backgroundColor: const Color(0xFF3A1A1A),
                  labelStyle: const TextStyle(
                    color: Color(0xFFFF8A80),
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _review(BuildContext context, String action) async {
    try {
      await context.read<ModerationService>().markReportReviewed(
        report.id,
        action: action,
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _removeFromGroup(BuildContext context) async {
    try {
      final moderation = context.read<ModerationService>();
      await moderation.removeReportedUserFromGroup(
        chatId: report.chatId,
        userId: report.reportedUserId,
      );
      await moderation.markReportReviewed(report.id, action: 'group_removed');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kullanıcı gruptan çıkarıldı.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }
}

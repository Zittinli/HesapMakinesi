import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/chat_format.dart';
import '../../models/auth_event_model.dart';
import '../../services/auth_log_service.dart';
import '../../services/auth_service.dart';
import '../chat/secret_hub_screen.dart';
import 'admin_reports_screen.dart';

class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({
    super.key,
    required this.onExitToCalculator,
  });

  final VoidCallback onExitToCalculator;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFF0B0B0B),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0B0B0B),
          foregroundColor: Colors.white70,
          elevation: 0,
          title: const Text(
            'Yonetim',
            style: TextStyle(fontWeight: FontWeight.w400),
          ),
          leading: IconButton(
            tooltip: 'Hesap makinesine don',
            icon: const Icon(Icons.close),
            onPressed: onExitToCalculator,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SecretHubScreen(
                      onExitToCalculator: onExitToCalculator,
                    ),
                  ),
                );
              },
              child: const Text(
                'Sohbetler',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            IconButton(
              tooltip: 'Cikis',
              icon: const Icon(Icons.logout, size: 20),
              onPressed: () => context.read<AuthService>().signOut(),
            ),
          ],
          bottom: const TabBar(
            indicatorColor: Colors.white70,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white38,
            tabs: [
              Tab(text: 'Bildirilenler'),
              Tab(text: 'Girisler'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            AdminReportsList(),
            _AuthEventsList(),
          ],
        ),
      ),
    );
  }
}

class _AuthEventsList extends StatelessWidget {
  const _AuthEventsList();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AuthEvent>>(
      stream: context.read<AuthLogService>().watchEvents(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Giris kayitlari okunamadi.\n${snapshot.error}',
                style: const TextStyle(color: Colors.white38),
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
        final events = snapshot.data!;
        if (events.isEmpty) {
          return const Center(
            child: Text(
              'Henuz giris kaydi yok.\nFirebase Console > Firestore > authEvents',
              style: TextStyle(color: Colors.white38, height: 1.5),
              textAlign: TextAlign.center,
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          itemCount: events.length,
          separatorBuilder: (_, __) =>
              const Divider(color: Color(0xFF222222), height: 1),
          itemBuilder: (context, index) {
            final event = events[index];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                event.email.isEmpty ? '(e-posta yok)' : event.email,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              subtitle: Text(
                [
                  event.label,
                  if (event.errorCode.isNotEmpty) event.errorCode,
                ].join(' · '),
                style: TextStyle(
                  color: event.success
                      ? Colors.white38
                      : const Color(0xFFFF8A80),
                  fontSize: 12,
                ),
              ),
              trailing: Text(
                ChatFormat.listTime(event.createdAt),
                style: const TextStyle(color: Colors.white30, fontSize: 12),
              ),
            );
          },
        );
      },
    );
  }
}

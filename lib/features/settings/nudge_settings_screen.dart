import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/chat_model.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/chat_service.dart';
import '../../services/nudge_haptic.dart';
import '../../services/nudge_service.dart';
import '../chat/chat_screen.dart';

class NudgeSettingsScreen extends StatelessWidget {
  const NudgeSettingsScreen({super.key, this.onExitToCalculator});

  final VoidCallback? onExitToCalculator;

  @override
  Widget build(BuildContext context) {
    final uid = context.read<AuthService>().currentUser!.uid;
    final chatService = context.read<ChatService>();

    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B0B),
        foregroundColor: Colors.white70,
        elevation: 0,
        title: const Text(
          'Dürtme',
          style: TextStyle(fontWeight: FontWeight.w400),
        ),
      ),
      body: StreamBuilder<List<ChatRoom>>(
        stream: chatService.watchUserChats(uid),
        builder: (context, chatSnapshot) {
          final directs = (chatSnapshot.data ?? const <ChatRoom>[])
              .where((chat) => !chat.isGroup && chat.participants.length == 2)
              .toList();
          return StreamBuilder<Map<String, bool>>(
            stream: chatService.watchMyNudgeAllows(uid),
            builder: (context, allowSnapshot) {
              final myAllows = allowSnapshot.data ?? const <String, bool>{};
              final allowedChats = directs.where((chat) {
                final peerId = chat.otherParticipantId(uid);
                return peerId.isNotEmpty && myAllows[peerId] == true;
              }).toList();
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  const Text(
                    'Titreşim gönder.',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  const _BatteryUnrestrictTile(),
                  const SizedBox(height: 20),
                  const Text(
                    'Beni dürtebilenler',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'İzin verdiklerin.',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  if (allowedChats.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 16, top: 8),
                      child: Text(
                        'Henüz kimse yok.',
                        style: TextStyle(color: Colors.white38),
                      ),
                    )
                  else
                    ...allowedChats.map((chat) {
                      final peerId = chat.otherParticipantId(uid);
                      return _NamedNudgeTile(
                        userId: peerId,
                        allowed: true,
                        onChanged: (value) {
                          chatService.setNudgeAllow(
                            userId: uid,
                            peerId: peerId,
                            chatId: chat.id,
                            allow: value,
                          );
                        },
                        onOpenChat: (user) => _openChat(
                          context,
                          chat: chat,
                          peerId: peerId,
                          name: user?.visibleName ?? 'Kişi',
                          email: user?.email,
                        ),
                      );
                    }),
                  const SizedBox(height: 20),
                  const Divider(color: Color(0xFF222222)),
                  const SizedBox(height: 16),
                  const Text(
                    'Benim dürtebildiklerim',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Sana izin verenler.',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  ...directs.map((chat) {
                    final peerId = chat.otherParticipantId(uid);
                    if (peerId.isEmpty) return const SizedBox.shrink();
                    return StreamBuilder<bool>(
                      stream: chatService.watchNudgeAllowed(
                        ownerId: peerId,
                        peerId: uid,
                      ),
                      builder: (context, canSnap) {
                        if (canSnap.data != true) {
                          return const SizedBox.shrink();
                        }
                        return _NamedNudgeTile(
                          userId: peerId,
                          allowed: true,
                          showSwitch: false,
                          onOpenChat: (user) => _openChat(
                            context,
                            chat: chat,
                            peerId: peerId,
                            name: user?.visibleName ?? 'Kişi',
                            email: user?.email,
                          ),
                          onNudge: () => _nudge(
                            context,
                            toId: peerId,
                            chatId: chat.id,
                          ),
                        );
                      },
                    );
                  }),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _nudge(
    BuildContext context, {
    required String toId,
    required String chatId,
  }) async {
    try {
      await context.read<NudgeService>().send(toId: toId, chatId: chatId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Dürtuldu.')));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', ''))),
      );
    }
  }

  void _openChat(
    BuildContext context, {
    required ChatRoom chat,
    required String peerId,
    required String name,
    String? email,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          chatId: chat.id,
          otherUserId: peerId,
          otherUserName: name,
          pendingEmail: email,
          onExitToCalculator: onExitToCalculator,
        ),
      ),
    );
  }
}

class _NamedNudgeTile extends StatelessWidget {
  const _NamedNudgeTile({
    required this.userId,
    required this.allowed,
    required this.onOpenChat,
    this.onChanged,
    this.onNudge,
    this.showSwitch = true,
  });

  final String userId;
  final bool allowed;
  final void Function(AppUser? user) onOpenChat;
  final ValueChanged<bool>? onChanged;
  final VoidCallback? onNudge;
  final bool showSwitch;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppUser?>(
      stream: context.read<AuthService>().watchUser(userId),
      builder: (context, snapshot) {
        final user = snapshot.data;
        final name = user?.visibleName ?? 'Kişi';
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(name, style: const TextStyle(color: Colors.white70)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showSwitch)
                Switch(
                  value: allowed,
                  onChanged: onChanged,
                  activeColor: Colors.white70,
                ),
              if (onNudge != null)
                IconButton(
                  tooltip: 'Dürt',
                  onPressed: onNudge,
                  icon: const Icon(Icons.vibration, color: Colors.white70),
                ),
              IconButton(
                tooltip: 'Sohbete git',
                onPressed: () => onOpenChat(user),
                icon: const Icon(
                  Icons.chat_bubble_outline,
                  color: Colors.white54,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BatteryUnrestrictTile extends StatefulWidget {
  const _BatteryUnrestrictTile();

  @override
  State<_BatteryUnrestrictTile> createState() => _BatteryUnrestrictTileState();
}

class _BatteryUnrestrictTileState extends State<_BatteryUnrestrictTile>
    with WidgetsBindingObserver {
  bool _unrestricted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    final value = await NudgeHaptic.isBatteryUnrestricted();
    if (!mounted) return;
    setState(() => _unrestricted = value);
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text(
        'Kapalıyken titreşim',
        style: TextStyle(color: Colors.white70),
      ),
      subtitle: Text(
        _unrestricted
            ? 'Android pil kısıtı kapalı. Samsung’da ayrıca Pil → Arka plan kullanımı → Hiç uyumayan uygulamalar’a ekle.'
            : 'Dokun, bu uygulama için kısıtı kaldır. Sonra Samsung’da Hiç uyumayan uygulamalar’a da ekle.',
        style: const TextStyle(color: Colors.white38, fontSize: 12),
      ),
      onTap: () => unawaited(NudgeHaptic.requestBatteryUnrestricted()),
    );
  }
}

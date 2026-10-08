import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/admin_config.dart';
import '../../core/chat_format.dart';
import '../../core/slide_from_right_route.dart';
import '../../models/chat_model.dart';
import '../../models/message_model.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/chat_service.dart';
import '../../services/storage_service.dart';
import '../../widgets/profile_avatar.dart';
import '../chat/media_viewer_screen.dart';
import 'admin_search_field.dart';

class FounderMediaPeopleScreen extends StatefulWidget {
  const FounderMediaPeopleScreen({super.key});

  @override
  State<FounderMediaPeopleScreen> createState() =>
      _FounderMediaPeopleScreenState();
}

class _FounderMediaPeopleScreenState extends State<FounderMediaPeopleScreen> {
  final _search = TextEditingController();
  Map<String, DateTime> _lastMediaAt = const {};
  bool _loadingTimes = true;

  bool get _founder {
    final auth = context.read<AuthService>();
    return AdminConfig.isFounder(
      email: auth.currentUser?.email,
      userId: auth.currentUser?.uid,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_founder) {
        Navigator.of(context).pop();
        return;
      }
      _reloadTimes();
    });
  }

  Future<void> _reloadTimes() async {
    try {
      final latest = await context.read<ChatService>().lastMediaAtBySender();
      if (!mounted) return;
      setState(() {
        _lastMediaAt = latest;
        _loadingTimes = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingTimes = false);
    }
  }

  List<AppUser> _sorted(List<AppUser> users) {
    final filtered = users
        .where(
          (user) => adminSearchMatches(_search.text, [
            user.visibleName,
            user.email,
            user.id,
          ]),
        )
        .toList();
    filtered.sort((a, b) {
      final at = _lastMediaAt[a.id];
      final bt = _lastMediaAt[b.id];
      if (at != null && bt != null) return bt.compareTo(at);
      if (at != null) return -1;
      if (bt != null) return 1;
      return a.visibleName.toLowerCase().compareTo(b.visibleName.toLowerCase());
    });
    return filtered;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_founder) {
      return const Scaffold(
        backgroundColor: Color(0xFF0B0B0B),
        body: SizedBox.shrink(),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B0B),
        foregroundColor: Colors.white70,
        elevation: 0,
      ),
      body: StreamBuilder<List<AppUser>>(
        stream: context.read<AuthService>().watchAllUsers(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Kişiler okunamadı.\n${snapshot.error}',
                style: const TextStyle(color: Colors.white38),
                textAlign: TextAlign.center,
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white24),
            );
          }
          final all = snapshot.data!;
          final users = _sorted(all);
          return Column(
            children: [
              AdminSearchField(
                controller: _search,
                hint: 'Ad veya e-posta ara',
                onChanged: (_) => setState(() {}),
              ),
              if (_loadingTimes)
                const LinearProgressIndicator(
                  minHeight: 1,
                  color: Colors.white24,
                  backgroundColor: Colors.transparent,
                ),
              Expanded(
                child: all.isEmpty
                    ? const Center(
                        child: Text(
                          'Henüz kullanıcı yok.',
                          style: TextStyle(color: Colors.white38),
                        ),
                      )
                    : users.isEmpty
                    ? const Center(
                        child: Text(
                          'Eşleşen kullanıcı yok.',
                          style: TextStyle(color: Colors.white38),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                        itemCount: users.length,
                        separatorBuilder: (_, __) =>
                            const Divider(color: Color(0xFF222222), height: 1),
                        itemBuilder: (context, index) {
                          final user = users[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: ProfileAvatar(
                              name: user.visibleName,
                              photoUrl: user.visiblePhotoUrl,
                              hidden: user.photoHidden,
                              radius: 20,
                            ),
                            title: Text(
                              user.visibleName,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              [
                                user.email,
                                if (_lastMediaAt[user.id] != null)
                                  ChatFormat.eventDateTime(
                                    _lastMediaAt[user.id],
                                  ),
                              ].join('\n'),
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 12,
                              ),
                            ),
                            isThreeLine: _lastMediaAt[user.id] != null,
                            onTap: () async {
                              await Navigator.of(context).push(
                                SlideFromRightPageRoute(
                                  builder: (_) =>
                                      FounderMediaListScreen(user: user),
                                ),
                              );
                              if (mounted) await _reloadTimes();
                            },
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class FounderMediaListScreen extends StatefulWidget {
  const FounderMediaListScreen({super.key, required this.user});

  final AppUser user;

  @override
  State<FounderMediaListScreen> createState() => _FounderMediaListScreenState();
}

class _FounderMediaListScreenState extends State<FounderMediaListScreen> {
  late final Future<_FounderMediaPage> _future = _load();

  bool get _founder {
    final auth = context.read<AuthService>();
    return AdminConfig.isFounder(
      email: auth.currentUser?.email,
      userId: auth.currentUser?.uid,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_founder) Navigator.of(context).pop();
    });
  }

  Future<_FounderMediaPage> _load() async {
    final chatService = context.read<ChatService>();
    final auth = context.read<AuthService>();
    final items = await chatService.listMediaSentBy(widget.user.id);
    final ids = <String>{};
    for (final item in items) {
      if (item.chat.isGroup) continue;
      final otherId = item.chat.otherParticipantId(widget.user.id);
      if (otherId.isNotEmpty) ids.add(otherId);
    }
    final peers = <String, AppUser>{};
    for (final id in ids) {
      final other = await auth.fetchUser(id);
      if (other != null) peers[id] = other;
    }
    return _FounderMediaPage(items: items, peers: peers);
  }

  String _sentTo(ChatRoom chat, Map<String, AppUser> peers) {
    if (chat.isGroup) {
      final name = chat.groupName.trim();
      return name.isEmpty ? 'Grup' : 'Grup · $name';
    }
    final otherId = chat.otherParticipantId(widget.user.id);
    final peer = peers[otherId];
    if (peer == null) return 'Kişi';
    return peer.visibleName;
  }

  Future<void> _open(SentMediaItem item) async {
    final locator = item.message.mediaUrl ?? '';
    if (locator.isEmpty) return;
    try {
      final file = item.message.isLocalMediaFile
          ? File(locator)
          : await context.read<StorageService>().downloadToCache(
              locator: locator,
              messageId: item.message.id,
              fileName: item.message.fileName,
            );
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MediaViewerScreen(
            url: locator,
            file: file,
            isVideo: item.message.type == MessageType.video,
          ),
        ),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (!_founder) {
      return const Scaffold(
        backgroundColor: Color(0xFF0B0B0B),
        body: SizedBox.shrink(),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B0B),
        foregroundColor: Colors.white70,
        elevation: 0,
        title: Text(
          widget.user.visibleName,
          style: const TextStyle(fontWeight: FontWeight.w400, fontSize: 16),
        ),
      ),
      body: FutureBuilder<_FounderMediaPage>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Medya okunamadı.\n${snapshot.error}',
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
          final page = snapshot.data!;
          if (page.items.isEmpty) {
            return const Center(
              child: Text(
                'Gönderilmiş fotoğraf veya video yok.',
                style: TextStyle(color: Colors.white38),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            itemCount: page.items.length,
            separatorBuilder: (_, __) =>
                const Divider(color: Color(0xFF222222), height: 16),
            itemBuilder: (context, index) {
              final item = page.items[index];
              final video = item.message.type == MessageType.video;
              return InkWell(
                onTap: () => _open(item),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MediaThumb(
                      locator: item.message.mediaUrl ?? '',
                      messageId: item.message.id,
                      fileName: item.message.fileName,
                      isVideo: video,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              video ? 'Video' : 'Fotoğraf',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _sentTo(item.chat, page.peers),
                              style: const TextStyle(
                                color: Colors.white38,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              ChatFormat.eventDateTime(item.message.createdAt),
                              style: const TextStyle(
                                color: Colors.white30,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _FounderMediaPage {
  const _FounderMediaPage({required this.items, required this.peers});

  final List<SentMediaItem> items;
  final Map<String, AppUser> peers;
}

class _MediaThumb extends StatefulWidget {
  const _MediaThumb({
    required this.locator,
    required this.messageId,
    required this.isVideo,
    this.fileName,
  });

  final String locator;
  final String messageId;
  final String? fileName;
  final bool isVideo;

  @override
  State<_MediaThumb> createState() => _MediaThumbState();
}

class _MediaThumbState extends State<_MediaThumb> {
  File? _file;

  @override
  void initState() {
    super.initState();
    if (!widget.isVideo && widget.locator.isNotEmpty) {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final file = widget.locator.startsWith('/') ||
              widget.locator.contains(':\\')
          ? File(widget.locator)
          : await context.read<StorageService>().downloadToCache(
              locator: widget.locator,
              messageId: widget.messageId,
              fileName: widget.fileName,
            );
      if (!mounted) return;
      setState(() => _file = file);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    return SizedBox(
      width: 120,
      height: 120,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: ColoredBox(
          color: const Color(0xFF161616),
          child: !widget.isVideo && file != null && file.existsSync()
              ? Image.file(file, fit: BoxFit.cover)
              : _icon(widget.isVideo),
        ),
      ),
    );
  }

  Widget _icon(bool video) {
    return Icon(
      video ? Icons.videocam_outlined : Icons.photo_outlined,
      color: Colors.white38,
      size: 36,
    );
  }
}

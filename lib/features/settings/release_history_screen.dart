import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/slide_from_right_route.dart';
import '../../services/release_notes_service.dart';

class ReleaseHistoryScreen extends StatefulWidget {
  const ReleaseHistoryScreen({super.key});

  @override
  State<ReleaseHistoryScreen> createState() => _ReleaseHistoryScreenState();
}

class _ReleaseHistoryScreenState extends State<ReleaseHistoryScreen> {
  final _service = ReleaseNotesService();
  late final Stream<List<ReleaseEntry>> _stream;

  @override
  void initState() {
    super.initState();
    _stream = _service.watchHistory();
    unawaited(_service.ensureHistorySeeded());
  }

  void _open(Widget page) {
    Navigator.of(context).push(
      SlideFromRightPageRoute<void>(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B0B),
        foregroundColor: Colors.white70,
        elevation: 0,
        title: const Text(
          'Önceki güncellemeler',
          style: TextStyle(fontWeight: FontWeight.w400),
        ),
        actions: [
          IconButton(
            tooltip: 'Sürüm ekle',
            onPressed: () => _open(ReleaseEditorScreen(service: _service)),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: StreamBuilder<List<ReleaseEntry>>(
        initialData: ReleaseNotesService.fallbackHistory,
        stream: _stream,
        builder: (context, snapshot) {
          final items = snapshot.hasError || snapshot.data == null
              ? ReleaseNotesService.fallbackHistory
              : snapshot.data!;
          if (items.isEmpty) {
            return const Center(
              child: Text(
                'Henüz sürüm yok.',
                style: TextStyle(color: Colors.white38),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(color: Color(0xFF222222)),
            itemBuilder: (context, index) {
              final entry = items[index];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  entry.version.isEmpty ? entry.notes.title : entry.version,
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
                subtitle: Text(
                  entry.notes.title,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                onTap: () => _open(
                  ReleaseNotesDetailScreen(entry: entry, service: _service),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class ReleaseNotesDetailScreen extends StatelessWidget {
  const ReleaseNotesDetailScreen({
    super.key,
    required this.entry,
    required this.service,
  });

  final ReleaseEntry entry;
  final ReleaseNotesService service;

  @override
  Widget build(BuildContext context) {
    final notes = entry.notes;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B0B),
        foregroundColor: Colors.white70,
        elevation: 0,
        title: Text(
          entry.version.isEmpty ? notes.title : entry.version,
          style: const TextStyle(fontWeight: FontWeight.w400),
        ),
        actions: [
          IconButton(
            tooltip: 'Düzenle',
            onPressed: () {
              Navigator.of(context).push(
                SlideFromRightPageRoute<void>(
                  builder: (_) => ReleaseEditorScreen(
                    service: service,
                    entry: entry,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            notes.title,
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 12),
          for (final item in notes.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '•  ',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class ReleaseEditorScreen extends StatefulWidget {
  const ReleaseEditorScreen({super.key, required this.service, this.entry});

  final ReleaseNotesService service;
  final ReleaseEntry? entry;

  @override
  State<ReleaseEditorScreen> createState() => _ReleaseEditorScreenState();
}

class _ReleaseEditorScreenState extends State<ReleaseEditorScreen> {
  late final TextEditingController _versionController;
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    _versionController = TextEditingController(text: entry?.version ?? '');
    _titleController = TextEditingController(text: entry?.notes.title ?? '');
    _bodyController = TextEditingController(text: entry?.notes.body ?? '');
  }

  @override
  void dispose() {
    _versionController.dispose();
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white30),
      filled: true,
      fillColor: const Color(0xFF1A1A1A),
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide.none,
      ),
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.service.saveHistory(
        id: widget.entry?.id,
        version: _versionController.text,
        title: _titleController.text,
        body: _bodyController.text,
        releasedAt: widget.entry?.releasedAt,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      if (widget.entry != null && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Sürüm kaydedilemedi.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.entry != null;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B0B),
        foregroundColor: Colors.white70,
        elevation: 0,
        title: Text(
          editing ? 'Sürümü düzenle' : 'Sürüm ekle',
          style: const TextStyle(fontWeight: FontWeight.w400),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          TextField(
            controller: _versionController,
            style: const TextStyle(color: Colors.white70),
            decoration: _decoration('Sürüm, ör. 1.7'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _titleController,
            style: const TextStyle(color: Colors.white70),
            decoration: _decoration('Başlık'),
          ),
          const SizedBox(height: 10),
          const Text(
            'Her satır bir madde.',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _bodyController,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              height: 1.4,
            ),
            minLines: 8,
            maxLines: 16,
            decoration: _decoration('Güncelleme notları'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Color(0xFFFF8A80))),
          ],
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2A2A2A),
              foregroundColor: Colors.white,
            ),
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Kaydediliyor...' : 'Kaydet'),
          ),
        ],
      ),
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/storage_service.dart';

Future<void> saveProfilePhoto(
  BuildContext context,
  String url, {
  File? file,
  String? cacheId,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final storage = context.read<StorageService>();
    final local = file;
    final saved = local != null && local.existsSync()
        ? local
        : await storage.downloadToCache(
            locator: url,
            messageId: cacheId ?? 'profile_${url.hashCode}',
            fileName: 'profil.jpg',
          );
    await storage.saveToGallery(saved, isVideo: false);
    messenger?.showSnackBar(
      const SnackBar(content: Text('Galeriye indirildi.')),
    );
  } catch (error) {
    debugPrint('HM_PROFILE_DOWNLOAD_FAILED: $error');
    messenger?.showSnackBar(
      const SnackBar(content: Text('Fotoğraf indirilemedi.')),
    );
  }
}

Future<void> openProfilePhoto(
  BuildContext context, {
  required String title,
  String? url,
  File? file,
}) {
  final photo = (url ?? '').trim();
  if (file == null && !photo.startsWith('http')) {
    return Future<void>.value();
  }
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ProfilePhotoView(
        title: title,
        url: photo,
        file: file,
      ),
    ),
  );
}

class ProfilePhotoView extends StatefulWidget {
  const ProfilePhotoView({
    super.key,
    required this.title,
    required this.url,
    this.file,
  });

  final String title;
  final String url;
  final File? file;

  @override
  State<ProfilePhotoView> createState() => _ProfilePhotoViewState();
}

class _ProfilePhotoViewState extends State<ProfilePhotoView> {
  bool _saving = false;

  Future<void> _download() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await saveProfilePhoto(
        context,
        widget.url,
        file: widget.file,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final local = widget.file;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white70,
        title: Text(
          widget.title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
        ),
        actions: [
          IconButton(
            tooltip: 'İndir',
            onPressed: _saving ? null : _download,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white70,
                    ),
                  )
                : const Icon(Icons.download_outlined),
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 5,
          child: local != null
              ? Image.file(
                  local,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Text(
                    'Fotoğraf açılamadı.',
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              : Image.network(
                  widget.url,
                  fit: BoxFit.contain,
                  loadingBuilder: (_, child, progress) {
                    if (progress == null) return child;
                    return const CircularProgressIndicator(
                      color: Colors.white24,
                    );
                  },
                  errorBuilder: (_, __, ___) => const Text(
                    'Fotoğraf açılamadı.',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
        ),
      ),
    );
  }
}

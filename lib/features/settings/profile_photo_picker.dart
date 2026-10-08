import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

Future<File?> pickProfilePhoto(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: const Color(0xFF161616),
    builder: (context) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: Colors.white70),
              title: const Text(
                'Fotoğraf çek',
                style: TextStyle(color: Colors.white70),
              ),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_outlined, color: Colors.white70),
              title: const Text(
                'Galeriden seç',
                style: TextStyle(color: Colors.white70),
              ),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.close, color: Colors.white38),
              title: const Text('Vazgeç', style: TextStyle(color: Colors.white38)),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      );
    },
  );
  if (source == null) return null;
  final picked = await ImagePicker().pickImage(
    source: source,
    imageQuality: 85,
    maxWidth: 1280,
    maxHeight: 1280,
  );
  if (picked == null) return null;
  return File(picked.path);
}

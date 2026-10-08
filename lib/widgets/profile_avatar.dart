import 'dart:io';

import 'package:flutter/material.dart';

import '../core/chat_format.dart';

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.name,
    this.photoUrl,
    this.hidden = false,
    this.file,
    this.radius = 20,
  });

  final String name;
  final String? photoUrl;
  final bool hidden;
  final File? file;
  final double radius;

  bool get _showPhoto {
    if (hidden) return false;
    if (file != null) return true;
    final url = photoUrl ?? '';
    return url.startsWith('http');
  }

  @override
  Widget build(BuildContext context) {
    final initials = ChatFormat.initials(name);
    ImageProvider? image;
    if (file != null && !hidden) {
      image = FileImage(file!);
    } else if (_showPhoto) {
      image = NetworkImage(photoUrl!);
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFF2A2A2A),
      backgroundImage: image,
      onBackgroundImageError: image == null ? null : (_, __) {},
      child: image == null
          ? Text(
              initials,
              style: TextStyle(
                color: Colors.white70,
                fontSize: radius * 0.62,
                fontWeight: FontWeight.w500,
              ),
            )
          : null,
    );
  }
}

import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
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
    if (file != null && !hidden) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: const Color(0xFF2A2A2A),
        backgroundImage: FileImage(file!),
        onBackgroundImageError: (_, __) {},
      );
    }
    if (!_showPhoto) return _initialsAvatar(initials);
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFF2A2A2A),
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: photoUrl!,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
          memCacheWidth: (radius * 6).round(),
          placeholder: (_, __) => _initialsMark(initials),
          errorWidget: (_, __, ___) => _initialsMark(initials),
        ),
      ),
    );
  }

  Widget _initialsAvatar(String initials) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFF2A2A2A),
      child: _initialsMark(initials),
    );
  }

  Widget _initialsMark(String initials) {
    return SizedBox(
      width: radius * 2,
      height: radius * 2,
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color: Colors.white70,
            fontSize: radius * 0.62,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_model.dart';

class PeerFace {
  const PeerFace({
    required this.name,
    required this.photoUrl,
    required this.photoHidden,
  });

  final String name;
  final String photoUrl;
  final bool photoHidden;

  String? get visiblePhotoUrl {
    if (photoHidden) return null;
    if (photoUrl.startsWith('http')) return photoUrl;
    return null;
  }

  @override
  bool operator ==(Object other) {
    return other is PeerFace &&
        other.name == name &&
        other.photoUrl == photoUrl &&
        other.photoHidden == photoHidden;
  }

  @override
  int get hashCode => Object.hash(name, photoUrl, photoHidden);
}

/// Sohbet listesi acilirken kisi belgesi agdan gelene kadar
/// son gorulen ad ve profil fotografini gosterir.
class PeerProfileCache {
  PeerProfileCache();

  static final instance = PeerProfileCache();

  String? _uid;
  SharedPreferences? _prefs;
  Future<void> _writes = Future<void>.value();
  final Map<String, PeerFace> _faces = {};

  Future<void> hydrate(String? uid) async {
    _faces.clear();
    _uid = (uid == null || uid.isEmpty) ? null : uid;
    if (_uid == null) return;
    _prefs ??= await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_key(_uid!));
    if (raw == null || raw.isEmpty) return;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return;
    decoded.forEach((key, value) {
      if (key is! String || value is! Map) return;
      final name = value['name'];
      if (name is! String || name.trim().isEmpty) return;
      final photo = value['photoUrl'];
      _faces[key] = PeerFace(
        name: name.trim(),
        photoUrl: photo is String ? photo : '',
        photoHidden: value['photoHidden'] == true,
      );
    });
  }

  Future<void> flush() => _writes;

  void clearMemory() {
    _uid = null;
    _faces.clear();
  }

  PeerFace? lookup(String userId) {
    if (userId.isEmpty) return null;
    return _faces[userId];
  }

  void remember(String ownerUid, AppUser user) {
    if (_uid == null || ownerUid != _uid || user.id.isEmpty) return;
    final face = PeerFace(
      name: user.visibleName,
      photoUrl: user.photoUrl,
      photoHidden: user.photoHidden,
    );
    if (face.name.isEmpty || _faces[user.id] == face) return;
    _faces[user.id] = face;
    _schedulePersist();
  }

  void _schedulePersist() {
    final uid = _uid;
    final prefs = _prefs;
    if (uid == null || prefs == null) return;
    final snapshot = Map<String, PeerFace>.from(_faces);
    _writes = _writes.then((_) async {
      if (_uid != uid) return;
      final payload = <String, Map<String, Object>>{
        for (final entry in snapshot.entries)
          entry.key: {
            'name': entry.value.name,
            'photoUrl': entry.value.photoUrl,
            'photoHidden': entry.value.photoHidden,
          },
      };
      await prefs.setString(_key(uid), jsonEncode(payload));
    });
  }

  static String _key(String uid) => 'peer_faces_$uid';
}

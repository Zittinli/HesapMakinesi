import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;

class StorageService {
  StorageService({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  Future<String> uploadChatMedia({
    required String folder,
    required File file,
    required String contentType,
  }) async {
    final ext = p.extension(file.path).isEmpty
        ? (contentType.startsWith('video/') ? '.mp4' : '.jpg')
        : p.extension(file.path);
    final name = '${DateTime.now().millisecondsSinceEpoch}$ext';
    final ref = _storage.ref().child('$folder/$name');
    await ref.putFile(
      file,
      SettableMetadata(contentType: contentType),
    );
    return ref.getDownloadURL();
  }

  Future<void> saveToGallery(File file, {required bool isVideo}) async {
    if (isVideo) {
      await Gal.putVideo(file.path);
    } else {
      await Gal.putImage(file.path);
    }
  }
}

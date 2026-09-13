import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class MediaUploadException implements Exception {
  const MediaUploadException(this.message);

  final String message;

  @override
  String toString() => message;
}

class StorageService {
  StorageService({FirebaseStorage? storage})
    : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;
  static const int maxUploadBytes = 40 * 1024 * 1024;

  Future<String> uploadChatMedia({
    required String folder,
    required File file,
    required String contentType,
  }) async {
    final fileSize = await file.length();
    if (fileSize > maxUploadBytes) {
      throw const MediaUploadException(
        'Video 40 MB sinirini asiyor. Daha kisa bir video deneyin.',
      );
    }
    final ext = p.extension(file.path).isEmpty
        ? (contentType.startsWith('video/') ? '.mp4' : '.jpg')
        : p.extension(file.path);
    final name = '${DateTime.now().millisecondsSinceEpoch}$ext';
    final ref = _storage.ref().child('$folder/$name');
    try {
      await ref.putFile(file, SettableMetadata(contentType: contentType));
      return await ref.getDownloadURL();
    } on FirebaseException catch (error) {
      throw MediaUploadException('Medya yuklenemedi (${error.code}).');
    }
  }

  Future<void> saveToGallery(File file, {required bool isVideo}) async {
    if (isVideo) {
      await Gal.putVideo(file.path);
    } else {
      await Gal.putImage(file.path);
    }
  }

  Future<void> downloadToGallery({
    required String mediaUrl,
    required bool isVideo,
  }) async {
    final dir = await getTemporaryDirectory();
    final ext = isVideo ? '.mp4' : '.jpg';
    final file = File(
      p.join(
        dir.path,
        'hm_download_${DateTime.now().millisecondsSinceEpoch}$ext',
      ),
    );
    await _storage.refFromURL(mediaUrl).writeToFile(file);
    await saveToGallery(file, isVideo: isVideo);
  }
}

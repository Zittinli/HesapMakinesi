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
  static const int maxUploadBytes = 75 * 1024 * 1024;

  Future<String> uploadChatMedia({
    required String folder,
    required File file,
    required String contentType,
    String? fileName,
  }) async {
    final fileSize = await file.length();
    if (fileSize > maxUploadBytes) {
      throw const MediaUploadException(
        'Dosya 75 MB sınırını aşıyor. Daha küçük bir dosya deneyin.',
      );
    }
    final ext = p.extension(fileName ?? file.path).isEmpty
        ? _fallbackExt(contentType)
        : p.extension(fileName ?? file.path);
    final name = '${DateTime.now().millisecondsSinceEpoch}$ext';
    final ref = _storage.ref().child('$folder/$name');
    try {
      await ref.putFile(
        file,
        SettableMetadata(
          contentType: contentType,
          contentDisposition: fileName == null
              ? null
              : 'attachment; filename="${p.basename(fileName)}"',
        ),
      );
      return await ref.getDownloadURL();
    } on FirebaseException catch (error) {
      throw MediaUploadException('Medya yüklenemedi (${error.code}).');
    }
  }

  static String _fallbackExt(String contentType) {
    if (contentType.startsWith('video/')) return '.mp4';
    if (contentType.startsWith('image/')) return '.jpg';
    if (contentType == 'application/pdf') return '.pdf';
    return '.bin';
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

  Future<File> downloadToDocuments({
    required String mediaUrl,
    required String fileName,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final safe = p.basename(fileName).replaceAll(RegExp(r'[^\w.\-]+'), '_');
    final file = File(
      p.join(
        dir.path,
        'hm_${DateTime.now().millisecondsSinceEpoch}_$safe',
      ),
    );
    await _storage.refFromURL(mediaUrl).writeToFile(file);
    return file;
  }
}

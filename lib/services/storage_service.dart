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
  static const int maxProfileBytes = 5 * 1024 * 1024;

  Future<String> uploadChatMedia({
    required String folder,
    required File file,
    required String contentType,
    String? fileName,
    String? ownerId,
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
    final owner = (ownerId ?? '').trim();
    final meta = SettableMetadata(
      contentType: _safeContentType(contentType),
      customMetadata: owner.isEmpty ? null : {'senderId': owner},
    );
    try {
      File upload = file;
      try {
        final dir = await getTemporaryDirectory();
        upload = await file.copy(p.join(dir.path, name));
      } catch (_) {}
      if (fileSize <= 12 * 1024 * 1024) {
        await ref.putData(await upload.readAsBytes(), meta);
      } else {
        await ref.putFile(upload, meta);
      }
      return ref.fullPath;
    } on FirebaseException catch (error) {
      throw MediaUploadException('Medya yüklenemedi (${error.code}).');
    } catch (_) {
      throw const MediaUploadException('Medya yüklenemedi.');
    }
  }

  static String _safeContentType(String raw) {
    final type = raw.split(';').first.trim().toLowerCase();
    if (type.startsWith('image/')) return type;
    if (type.startsWith('video/')) return type;
    if (type.startsWith('audio/')) return type;
    if (type.startsWith('text/')) return type;
    if (type.startsWith('application/')) return type;
    if (type.startsWith('image')) return 'image/jpeg';
    if (type.startsWith('video')) return 'video/mp4';
    return 'application/octet-stream';
  }

  static String _fallbackExt(String contentType) {
    if (contentType.startsWith('video/')) return '.mp4';
    if (contentType.startsWith('image/')) return '.jpg';
    if (contentType == 'application/pdf') return '.pdf';
    return '.bin';
  }

  Future<String> uploadProfilePhoto({
    required String folder,
    required File file,
  }) async {
    final fileSize = await file.length();
    if (fileSize > maxProfileBytes) {
      throw const MediaUploadException(
        'Profil fotoğrafı 5 MB sınırını aşıyor.',
      );
    }
    final name = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ref = _storage.ref().child('$folder/$name');
    final meta = SettableMetadata(contentType: 'image/jpeg');
    try {
      await ref.putData(await file.readAsBytes(), meta);
      return await ref.getDownloadURL();
    } on FirebaseException catch (error) {
      throw MediaUploadException('Fotoğraf yüklenemedi (${error.code}).');
    } catch (_) {
      throw const MediaUploadException('Fotoğraf yüklenemedi.');
    }
  }

  Future<void> saveToGallery(File file, {required bool isVideo}) async {
    if (isVideo) {
      await Gal.putVideo(file.path);
    } else {
      await Gal.putImage(file.path);
    }
  }

  Reference refFor(String locator) {
    final trimmed = locator.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return _storage.refFromURL(trimmed);
    }
    return _storage.ref(trimmed);
  }

  Future<File> persistChatFile({
    required String id,
    required File file,
    String? fileName,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory(p.join(dir.path, 'media_cache'));
    if (!folder.existsSync()) {
      await folder.create(recursive: true);
    }
    final ext = p.extension(fileName ?? file.path);
    final safe = id.replaceAll(RegExp(r'[^\w.\-]+'), '_');
    final dest = File(p.join(folder.path, '$safe$ext'));
    if (file.path == dest.path) return dest;
    await file.copy(dest.path);
    return dest;
  }

  Future<File> downloadToCache({
    required String locator,
    required String messageId,
    String? fileName,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory(p.join(dir.path, 'media_cache'));
    if (!folder.existsSync()) {
      await folder.create(recursive: true);
    }
    final ext = p.extension(fileName ?? locator);
    final safe = messageId.replaceAll(RegExp(r'[^\w.\-]+'), '_');
    final dest = File(p.join(folder.path, '$safe$ext'));
    if (await dest.exists() && await dest.length() > 0) {
      return dest;
    }
    await refFor(locator).writeToFile(dest);
    return dest;
  }

  Future<void> downloadToGallery({
    required String locator,
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
    await refFor(locator).writeToFile(file);
    await saveToGallery(file, isVideo: isVideo);
  }

  Future<File> downloadToDocuments({
    required String locator,
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
    await refFor(locator).writeToFile(file);
    return file;
  }
}

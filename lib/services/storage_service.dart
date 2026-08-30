import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class StorageService {
  StorageService({FirebaseStorage? storage, ImagePicker? picker})
      : _storage = storage ?? FirebaseStorage.instance,
        _picker = picker ?? ImagePicker();

  final FirebaseStorage _storage;
  final ImagePicker _picker;

  Future<XFile?> pickImage() {
    return _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
  }

  Future<String> uploadChatImage({
    required String chatId,
    required File file,
  }) async {
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ref = _storage.ref().child('chat_media/$chatId/$fileName');
    await ref.putFile(file);
    return ref.getDownloadURL();
  }
}

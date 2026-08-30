import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Firebase yapilandirmasi.
///
/// Gercek anahtarlar icin proje kokunde su komutu calistirin:
/// dart pub global activate flutterfire_cli
/// flutterfire configure
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError('Linux henuz desteklenmiyor.');
      default:
        throw UnsupportedError('Bu platform desteklenmiyor.');
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAkgFAJv7kNEobOV6szSwK3FF2vYl3LTno',
    appId: '1:566929853130:web:b95a402abeb6381e634233',
    messagingSenderId: '566929853130',
    projectId: 'hesapmakinesi-d8f57',
    authDomain: 'hesapmakinesi-d8f57.firebaseapp.com',
    storageBucket: 'hesapmakinesi-d8f57.firebasestorage.app',
    measurementId: 'G-30B86Z64SV',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyD5z0UvRtySoPs61BMJLizUzVqATHNXghE',
    appId: '1:566929853130:android:a0e7ae76e86fe0cb634233',
    messagingSenderId: '566929853130',
    projectId: 'hesapmakinesi-d8f57',
    storageBucket: 'hesapmakinesi-d8f57.firebasestorage.app',
  );
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCQT-ClHDZJmYg3-qj03D3ShKZNyegfYy8',
    appId: '1:566929853130:ios:25b6db9826bd1e95634233',
    messagingSenderId: '566929853130',
    projectId: 'hesapmakinesi-d8f57',
    storageBucket: 'hesapmakinesi-d8f57.firebasestorage.app',
    iosBundleId: 'com.hesapmakinesi.hesapMakinesi',
  );
  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyCQT-ClHDZJmYg3-qj03D3ShKZNyegfYy8',
    appId: '1:566929853130:ios:25b6db9826bd1e95634233',
    messagingSenderId: '566929853130',
    projectId: 'hesapmakinesi-d8f57',
    storageBucket: 'hesapmakinesi-d8f57.firebasestorage.app',
    iosBundleId: 'com.hesapmakinesi.hesapMakinesi',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyAkgFAJv7kNEobOV6szSwK3FF2vYl3LTno',
    appId: '1:566929853130:web:df85fa10503ea598634233',
    messagingSenderId: '566929853130',
    projectId: 'hesapmakinesi-d8f57',
    authDomain: 'hesapmakinesi-d8f57.firebaseapp.com',
    storageBucket: 'hesapmakinesi-d8f57.firebasestorage.app',
    measurementId: 'G-WDQ8QK3K83',
  );
}

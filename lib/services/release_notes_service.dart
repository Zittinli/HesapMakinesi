import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ReleaseNotes {
  const ReleaseNotes({required this.title, required this.items});

  final String title;
  final List<String> items;

  static const defaults = ReleaseNotes(
    title: '1.7 güncellemesi',
    items: [
      'Mesajdaki bağlantı farklı yazılır; basınca Instagram, TikTok veya tarayıcı açılır.',
      'Mesajı sağa kaydırarak yanıtlanır. Yanıta basınca o mesaja gidilir.',
      'Sohbet ve mesaj arama çalışır.',
      'Grupta yönetici atama, ad değiştirme ve üye çıkarma düzeltildi.',
      'Mesaj ayrıntısında kimin ne zaman gördüğü yazılır.',
      'Bildirimler kapalıyken de gelir; kilit ekranında kapak metni görünür.',
      'Dürtme eklendi. Sohbette titreşim gönderilir; izin Gizlilik’ten verilir.',
      'Boşta kalınca hesap makinesine dönüş. Süre saniye olarak yazılabilir. Son 15 saniye bordo uyarır.',
      'Video çekilirken kamera çevrilebilir. Fotoğraf ve video oranları korunur.',
      'Yükleme sürerken başka mesaj da gönderilebilir. İletilince gri, görülünce mavi tik.',
      'Kayıtta şifre tekrar yazılır; şifre gösterilebilir.',
      'Varsayılan ikon Samsung’dur. Klasik tema eski ikonu kullanır.',
      'Ayarlar alt sayfalara ayrıldı; sayfalar sağdan açılır.',
    ],
  );

  static const v16 = ReleaseNotes(
    title: '1.6 güncellemesi',
    items: [
      'Fotoğraf ve video uygulamadan çekilip gönderilir; galeriye kaydedilmez.',
      'Sohbet en alttan açılır. Yukarı kayınca aşağı in tuşu çıkar.',
      'Sohbet ve mesaj arama eklendi.',
      'Medya oranları korunur.',
      'Gönderilince gri, görülünce mavi tik.',
    ],
  );

  String get body => items.join('\n');

  static List<String> itemsFromBody(String body) {
    return body
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  static ReleaseNotes fromData(Map<String, dynamic> data) {
    final title = (data['title'] as String? ?? '').trim();
    final body = data['body'] as String? ?? '';
    final items = itemsFromBody(body);
    if (title.isEmpty && items.isEmpty) return defaults;
    return ReleaseNotes(
      title: title.isEmpty ? defaults.title : title,
      items: items,
    );
  }
}

class ReleaseEntry {
  const ReleaseEntry({
    required this.id,
    required this.version,
    required this.notes,
    this.releasedAt,
  });

  final String id;
  final String version;
  final ReleaseNotes notes;
  final DateTime? releasedAt;
}

class ReleaseNotesService {
  ReleaseNotesService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  DocumentReference<Map<String, dynamic>> get _doc =>
      _firestore.collection('appConfig').doc('releaseNotes');

  CollectionReference<Map<String, dynamic>> get _history =>
      _firestore.collection('releaseHistory');

  static final fallbackHistory = <ReleaseEntry>[
    ReleaseEntry(
      id: 'v1_7',
      version: '1.7',
      notes: ReleaseNotes.defaults,
      releasedAt: DateTime(2026, 9, 19),
    ),
    ReleaseEntry(
      id: 'v1_6',
      version: '1.6',
      notes: ReleaseNotes.v16,
      releasedAt: DateTime(2026, 9, 13),
    ),
  ];

  Stream<ReleaseNotes> watch() {
    return _doc
        .snapshots()
        .map((snap) {
          if (!snap.exists) return ReleaseNotes.defaults;
          final data = snap.data();
          if (data == null) return ReleaseNotes.defaults;
          return ReleaseNotes.fromData(data);
        })
        .handleError((_, __) {});
  }

  Future<void> save({required String title, required String body}) async {
    final uid = _requireUid();
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty) {
      throw ArgumentError('Başlık boş olamaz.');
    }
    await _doc.set({
      'title': trimmedTitle,
      'body': body.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': uid,
    });
  }

  Stream<List<ReleaseEntry>> watchHistory() {
    return _history
        .orderBy('releasedAt', descending: true)
        .snapshots()
        .map((snap) {
          if (snap.docs.isEmpty) return fallbackHistory;
          return snap.docs.map(_entryFromDoc).toList();
        })
        .handleError((_, __) {});
  }

  Future<void> ensureHistorySeeded() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final existing = await _history.limit(1).get();
    if (existing.docs.isNotEmpty) return;
    final batch = _firestore.batch();
    for (final entry in fallbackHistory) {
      batch.set(
        _history.doc(entry.id),
        _historyPayload(
          version: entry.version,
          title: entry.notes.title,
          body: entry.notes.body,
          releasedAt: entry.releasedAt ?? DateTime.now(),
          uid: uid,
        ),
      );
    }
    await batch.commit();
  }

  Future<void> saveHistory({
    String? id,
    required String version,
    required String title,
    required String body,
    DateTime? releasedAt,
  }) async {
    final uid = _requireUid();
    final trimmedVersion = version.trim();
    final trimmedTitle = title.trim();
    if (trimmedVersion.isEmpty || trimmedTitle.isEmpty) {
      throw ArgumentError('Sürüm ve başlık gerekli.');
    }
    final docId = id ?? 'v${trimmedVersion.replaceAll('.', '_')}';
    await _history.doc(docId).set(
      _historyPayload(
        version: trimmedVersion,
        title: trimmedTitle,
        body: body.trim(),
        releasedAt: releasedAt ?? DateTime.now(),
        uid: uid,
      ),
    );
  }

  ReleaseEntry _entryFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final releasedAt = data['releasedAt'];
    return ReleaseEntry(
      id: doc.id,
      version: (data['version'] as String? ?? '').trim(),
      notes: ReleaseNotes.fromData({
        'title': data['title'],
        'body': data['body'],
      }),
      releasedAt: releasedAt is Timestamp ? releasedAt.toDate() : null,
    );
  }

  Map<String, dynamic> _historyPayload({
    required String version,
    required String title,
    required String body,
    required DateTime releasedAt,
    required String uid,
  }) {
    return {
      'version': version,
      'title': title,
      'body': body,
      'releasedAt': Timestamp.fromDate(releasedAt),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': uid,
    };
  }

  String _requireUid() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw StateError('Oturum yok.');
    }
    return uid;
  }
}

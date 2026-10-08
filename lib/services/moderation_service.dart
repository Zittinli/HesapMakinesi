import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/admin_config.dart';
import '../core/staff_perms.dart';
import '../models/message_model.dart';
import '../models/moderation_model.dart';
import '../models/report_model.dart';
import 'chat_service.dart';

class ModerationService {
  ModerationService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _reports =>
      _firestore.collection('reports');
  CollectionReference<Map<String, dynamic>> get _moderation =>
      _firestore.collection('moderation');
  CollectionReference<Map<String, dynamic>> get _bannedEmails =>
      _firestore.collection('bannedEmails');

  bool get isAdmin => AdminConfig.isAdminEmail(_auth.currentUser?.email);

  bool get isFounder => AdminConfig.isFounder(
        email: _auth.currentUser?.email,
        userId: _auth.currentUser?.uid,
      );

  Future<Set<String>> myStaffPerms() async {
    if (isFounder) return StaffPerm.all.toSet();
    final uid = _auth.currentUser?.uid;
    if (uid == null) return {};
    final snap = await _firestore.collection('users').doc(uid).get();
    final raw = List<String>.from(snap.data()?['staffPerms'] as List? ?? const []);
    return StaffPerm.normalize(raw);
  }

  Future<bool> hasStaffPerm(String perm) async {
    if (isFounder) return true;
    return (await myStaffPerms()).contains(perm);
  }

  Future<void> _requirePerm(String perm) async {
    if (!await hasStaffPerm(perm)) {
      throw StateError('Bu işlem için yetki yok.');
    }
  }

  static String emailDocId(String email) => email.trim().toLowerCase();

  Stream<ModerationStatus> watchRestriction({
    required String userId,
    required String email,
  }) {
    final controller = StreamController<ModerationStatus>();
    var uidStatus = ModerationStatus.empty;
    var emailStatus = ModerationStatus.empty;

    void emit() {
      if (!controller.isClosed) {
        controller.add(ModerationStatus.stricter(uidStatus, emailStatus));
      }
    }

    final uidSub = _moderation.doc(userId).snapshots().listen((doc) {
      uidStatus = ModerationStatus.fromMap(doc.data());
      emit();
    });
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? emailSub;
    if (email.trim().isNotEmpty) {
      emailSub = _bannedEmails.doc(emailDocId(email)).snapshots().listen((doc) {
        emailStatus = ModerationStatus.fromMap(doc.data());
        emit();
      });
    }

    controller.onCancel = () async {
      await uidSub.cancel();
      await emailSub?.cancel();
    };
    return controller.stream;
  }

  Future<ModerationStatus> getRestriction({
    required String userId,
    required String email,
  }) async {
    final uidSnap = await _moderation.doc(userId).get();
    var status = ModerationStatus.fromMap(uidSnap.data());
    if (email.trim().isNotEmpty) {
      final emailSnap = await _bannedEmails.doc(emailDocId(email)).get();
      status = ModerationStatus.stricter(
        status,
        ModerationStatus.fromMap(emailSnap.data()),
      );
    }
    return status;
  }

  Future<void> ensureNotRestricted(String userId, String email) async {
    if (AdminConfig.isAdminEmail(email)) return;
    final status = await getRestriction(userId: userId, email: email);
    if (status.isRestricted()) {
      throw AccountRestrictedException(status.label);
    }
  }

  Future<void> reportMessage({
    required ChatMessage message,
    required String chatId,
    required String reportedUserId,
    required String reportedEmail,
    required ReportReason reason,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;
    if (message.senderId == user.uid) return;
    final context = await _reportContext(chatId, reportedUserId);

    await _createReport(
      reporter: user,
      chatId: chatId,
      reportedUserId: reportedUserId,
      reportedEmail: context.email.isNotEmpty ? context.email : reportedEmail,
      reason: reason,
      messageId: message.id,
      messageText: message.text,
      isGroup: context.isGroup,
      groupName: context.groupName,
    );
  }

  /// Belirli bir mesaja bagli olmadan kisiyi bildirir. Kanit olarak
  /// karsi tarafin son mesaji kullanilir, yoksa mesaj alanlari bos kalir.
  Future<void> reportUser({
    required String chatId,
    required String reportedUserId,
    required String reportedEmail,
    required ReportReason reason,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;
    if (reportedUserId == user.uid) return;
    final context = await _reportContext(chatId, reportedUserId);

    final history = await _snapshotHistory(chatId, reportedMessageId: '');
    Map<String, dynamic>? lastFromReported;
    for (final item in history) {
      if ((item['senderId'] as String? ?? '') == reportedUserId) {
        lastFromReported = item;
      }
    }

    await _createReport(
      reporter: user,
      chatId: chatId,
      reportedUserId: reportedUserId,
      reportedEmail: context.email.isNotEmpty ? context.email : reportedEmail,
      reason: reason,
      messageId: (lastFromReported?['messageId'] as String? ?? '').isEmpty
          ? 'kisi-bildirimi'
          : lastFromReported!['messageId'] as String,
      messageText: lastFromReported?['text'] as String? ?? '',
      isGroup: context.isGroup,
      groupName: context.groupName,
    );
  }

  Future<({String email, bool isGroup, String groupName})> _reportContext(
    String chatId,
    String reportedUserId,
  ) async {
    try {
      final results = await Future.wait([
        _firestore.collection('users').doc(reportedUserId).get(),
        _firestore.collection('chats').doc(chatId).get(),
      ]);
      final userData = results[0].data();
      final chatData = results[1].data();
      return (
        email: userData?['email'] as String? ?? '',
        isGroup: chatData?['isGroup'] as bool? ?? false,
        groupName: chatData?['groupName'] as String? ?? '',
      );
    } catch (_) {
      return (email: '', isGroup: false, groupName: '');
    }
  }

  Future<void> _createReport({
    required User reporter,
    required String chatId,
    required String reportedUserId,
    required String reportedEmail,
    required ReportReason reason,
    required String messageId,
    required String messageText,
    bool isGroup = false,
    String groupName = '',
  }) async {
    final history = await _snapshotHistory(
      chatId,
      reportedMessageId: messageId,
    );
    final transcript = _formatTranscript(
      history,
      reporterId: reporter.uid,
      reportedUserId: reportedUserId,
    );

    final reportRef = _reports.doc();
    await reportRef.set({
      'reporterId': reporter.uid,
      'reporterEmail': (reporter.email ?? '').toLowerCase(),
      'reportedUserId': reportedUserId,
      'reportedEmail': reportedEmail.trim().toLowerCase(),
      'chatId': chatId,
      'messageId': messageId,
      'messageText': messageText.length > 4000
          ? messageText.substring(0, 4000)
          : messageText,
      'reason': reason.name,
      'status': 'pending',
      'action': '',
      'createdAt': FieldValue.serverTimestamp(),
      'history': history,
      'transcript': transcript,
      'historyCount': history.length,
      'isGroup': isGroup,
      'groupName': groupName.length > 80
          ? groupName.substring(0, 80)
          : groupName,
    });

    if (history.isNotEmpty) {
      final batch = _firestore.batch();
      for (final item in history) {
        final id = (item['messageId'] as String?) ?? '';
        if (id.isEmpty) continue;
        batch.set(reportRef.collection('history').doc(id), item);
      }
      await batch.commit();
    }
  }

  Future<List<Map<String, dynamic>>> _snapshotHistory(
    String chatId, {
    required String reportedMessageId,
  }) async {
    if (chatId.isEmpty) return const [];
    try {
      final snap = await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .orderBy('createdAt')
          .limitToLast(80)
          .get();
      return snap.docs.map((doc) {
        final data = doc.data();
        final text = (data['text'] as String? ?? '');
        return <String, dynamic>{
          'messageId': doc.id,
          'senderId': data['senderId'] as String? ?? '',
          'text': text.length > 500 ? text.substring(0, 500) : text,
          'createdAt': data['createdAt'],
          'reported': doc.id == reportedMessageId,
        };
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  String _formatTranscript(
    List<Map<String, dynamic>> history, {
    required String reporterId,
    required String reportedUserId,
  }) {
    if (history.isEmpty) return '';
    final buffer = StringBuffer();
    for (final item in history) {
      final createdAt = item['createdAt'];
      var time = '';
      if (createdAt is Timestamp) {
        final dt = createdAt.toDate();
        time =
            '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')} '
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
      final senderId = item['senderId'] as String? ?? '';
      final who = senderId == reportedUserId
          ? 'sikayet-edilen'
          : (senderId == reporterId ? 'bildiren' : senderId);
      final mark = item['reported'] == true ? ' [BILDIRILEN]' : '';
      buffer.writeln('$time $who: ${item['text']}$mark');
    }
    final text = buffer.toString();
    if (text.length <= 20000) return text;
    return text.substring(text.length - 20000);
  }

  Stream<List<MessageReport>> watchReports() {
    return _reports
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots()
        .map((snap) => snap.docs.map(MessageReport.fromFirestore).toList());
  }

  Future<void> markReportReviewed(String reportId, {String action = ''}) {
    return _reports.doc(reportId).update({
      'status': action.isEmpty ? 'reviewed' : 'actioned',
      'action': action,
      'reviewedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> applyPenalty({
    required String userId,
    required String email,
    required String reason,
    Duration? timeout,
    bool permanent = false,
  }) async {
    if (AdminConfig.isFounder(email: email, userId: userId)) {
      throw StateError('Kurucu yöneticiye ceza uygulanamaz.');
    }
    final admin = _auth.currentUser;
    if (admin == null) throw StateError('Bu işlem için yetki yok.');
    await _requirePerm(StaffPerm.punishReports);

    final existing = userId.isEmpty
        ? null
        : await _moderation.doc(userId).get();
    final hide = existing?.data()?['hideProfilePhoto'] == true;

    final payload = <String, dynamic>{
      'bannedPermanently': permanent,
      'timeoutUntil': timeout == null
          ? null
          : Timestamp.fromDate(DateTime.now().add(timeout)),
      'reason': reason.length > 400 ? reason.substring(0, 400) : reason,
      'email': email.trim().toLowerCase(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': admin.uid,
      'hideProfilePhoto': hide,
    };

    final batch = _firestore.batch();
    if (userId.isNotEmpty) {
      batch.set(_moderation.doc(userId), payload, SetOptions(merge: true));
    }
    if (email.trim().isNotEmpty) {
      batch.set(_bannedEmails.doc(emailDocId(email)), payload, SetOptions(merge: true));
    }
    await batch.commit();
  }

  Future<void> setProfilePhotoHidden({
    required String userId,
    required String email,
    required bool hidden,
  }) async {
    if (AdminConfig.isFounder(email: email, userId: userId)) {
      throw StateError('Kurucu yöneticinin fotoğrafı gizlenemez.');
    }
    final admin = _auth.currentUser;
    if (admin == null) throw StateError('Bu işlem için yetki yok.');
    await _requirePerm(StaffPerm.punishReports);
    final payload = <String, dynamic>{
      'hideProfilePhoto': hidden,
      'email': email.trim().toLowerCase(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': admin.uid,
    };
    final batch = _firestore.batch();
    if (userId.isNotEmpty) {
      batch.set(_moderation.doc(userId), payload, SetOptions(merge: true));
      batch.update(_firestore.collection('users').doc(userId), {
        'photoHidden': hidden,
      });
    }
    if (email.trim().isNotEmpty) {
      batch.set(_bannedEmails.doc(emailDocId(email)), payload, SetOptions(merge: true));
    }
    await batch.commit();
  }

  Future<void> clearPenalty({
    required String userId,
    required String email,
  }) async {
    final admin = _auth.currentUser;
    if (admin == null) throw StateError('Bu işlem için yetki yok.');
    await _requirePerm(StaffPerm.punishReports);
    final payload = <String, dynamic>{
      'bannedPermanently': false,
      'timeoutUntil': null,
      'reason': '',
      'email': email.trim().toLowerCase(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': admin.uid,
    };
    final batch = _firestore.batch();
    if (userId.isNotEmpty) {
      batch.set(_moderation.doc(userId), payload, SetOptions(merge: true));
    }
    if (email.trim().isNotEmpty) {
      batch.set(_bannedEmails.doc(emailDocId(email)), payload, SetOptions(merge: true));
    }
    await batch.commit();
  }

  Future<void> timeoutGroup({
    required String chatId,
    Duration? timeout,
  }) async {
    await _requirePerm(StaffPerm.timeoutGroup);
    await ChatService(firestore: _firestore).setGroupTimeout(
      chatId: chatId,
      timeout: timeout,
    );
  }

  Future<void> removeReportedUserFromGroup({
    required String chatId,
    required String userId,
  }) async {
    await _requirePerm(StaffPerm.punishReports);
    await ChatService(
      firestore: _firestore,
    ).appAdminRemoveFromGroup(chatId: chatId, userId: userId);
  }

  Future<int> removeReportedUserFromAllGroups(String userId) async {
    await _requirePerm(StaffPerm.punishReports);
    return ChatService(
      firestore: _firestore,
    ).appAdminRemoveFromAllGroups(userId);
  }
}

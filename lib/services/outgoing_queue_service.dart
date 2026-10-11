import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/message_model.dart';
import 'chat_service.dart';
import 'settings_service.dart';
import 'storage_service.dart';

enum OutgoingFailureKind { retry, drop }

OutgoingFailureKind classifyOutgoingFailure(Object error) {
  if (error is FileSystemException || error is ChatBlockedException) {
    return OutgoingFailureKind.drop;
  }
  final raw = error.toString().toLowerCase();
  if (error is MediaUploadException) {
    const retryCodes = [
      '(unknown)',
      '(retry-limit-exceeded)',
      '(unavailable)',
      '(deadline-exceeded)',
      '(cancelled)',
      '(canceled)',
      '(internal)',
      '(network-request-failed)',
    ];
    for (final code in retryCodes) {
      if (raw.contains(code)) return OutgoingFailureKind.retry;
    }
    if (raw == 'medya yüklenemedi.') return OutgoingFailureKind.retry;
    return OutgoingFailureKind.drop;
  }
  const permanent = [
    'permission-denied',
    'permission_denied',
    'unauthenticated',
    'unauthorized',
    'invalid-argument',
    'failed-precondition',
    'not-found',
    'object-not-found',
    'quota-exceeded',
  ];
  for (final code in permanent) {
    if (raw.contains(code)) return OutgoingFailureKind.drop;
  }
  return OutgoingFailureKind.retry;
}

class OutgoingJob {
  const OutgoingJob({
    required this.id,
    required this.senderId,
    required this.createdAtMs,
    required this.text,
    required this.type,
    this.chatId = '',
    this.pendingEmail = '',
    this.replyToId,
    this.replyToText,
    this.replyToSenderId,
    this.expireSeconds,
    this.localPath,
    this.fileName,
    this.fileSize,
    this.fileMime,
    this.remotePath,
    this.attempts = 0,
    this.nextAttemptMs = 0,
    this.status = 'queued',
  });

  final String id;
  final String senderId;
  final int createdAtMs;
  final String text;
  final MessageType type;
  final String chatId;
  final String pendingEmail;
  final String? replyToId;
  final String? replyToText;
  final String? replyToSenderId;
  final int? expireSeconds;
  final String? localPath;
  final String? fileName;
  final int? fileSize;
  final String? fileMime;
  final String? remotePath;
  final int attempts;
  final int nextAttemptMs;
  final String status;

  bool get isMedia =>
      type == MessageType.image ||
      type == MessageType.video ||
      type == MessageType.file;

  bool get isPendingEmail => chatId.isEmpty && pendingEmail.isNotEmpty;

  ChatMessage toMessage() {
    return ChatMessage(
      id: id,
      senderId: senderId,
      text: text,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMs),
      readBy: [senderId],
      type: type,
      mediaUrl: localPath,
      fileName: fileName,
      fileSize: fileSize,
      fileMime: fileMime,
      replyToId: replyToId,
      replyToText: replyToText,
      replyToSenderId: replyToSenderId,
      expireSeconds: expireSeconds,
      expiresAt: expireSeconds == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              createdAtMs,
            ).add(Duration(seconds: expireSeconds!)),
      pendingWrite: true,
      clientKey: id,
    );
  }

  OutgoingJob copyWith({
    String? status,
    String? localPath,
    int? fileSize,
    String? remotePath,
    int? attempts,
    int? nextAttemptMs,
  }) {
    return OutgoingJob(
      id: id,
      senderId: senderId,
      createdAtMs: createdAtMs,
      text: text,
      type: type,
      chatId: chatId,
      pendingEmail: pendingEmail,
      replyToId: replyToId,
      replyToText: replyToText,
      replyToSenderId: replyToSenderId,
      expireSeconds: expireSeconds,
      localPath: localPath ?? this.localPath,
      fileName: fileName,
      fileSize: fileSize ?? this.fileSize,
      fileMime: fileMime,
      remotePath: remotePath ?? this.remotePath,
      attempts: attempts ?? this.attempts,
      nextAttemptMs: nextAttemptMs ?? this.nextAttemptMs,
      status: status ?? this.status,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'senderId': senderId,
        'createdAtMs': createdAtMs,
        'text': text,
        'type': ChatMessage.typeRaw(type),
        'chatId': chatId,
        'pendingEmail': pendingEmail,
        'replyToId': replyToId,
        'replyToText': replyToText,
        'replyToSenderId': replyToSenderId,
        'expireSeconds': expireSeconds,
        'localPath': localPath,
        'fileName': fileName,
        'fileSize': fileSize,
        'fileMime': fileMime,
        'remotePath': remotePath,
        'attempts': attempts,
        'nextAttemptMs': nextAttemptMs,
        'status': status,
      };

  factory OutgoingJob.fromJson(Map<String, dynamic> json) {
    return OutgoingJob(
      id: json['id'] as String? ?? '',
      senderId: json['senderId'] as String? ?? '',
      createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
      text: json['text'] as String? ?? '',
      type: ChatMessage.typeFrom(json['type'] as String?),
      chatId: json['chatId'] as String? ?? '',
      pendingEmail: json['pendingEmail'] as String? ?? '',
      replyToId: json['replyToId'] as String?,
      replyToText: json['replyToText'] as String?,
      replyToSenderId: json['replyToSenderId'] as String?,
      expireSeconds: (json['expireSeconds'] as num?)?.toInt(),
      localPath: json['localPath'] as String?,
      fileName: json['fileName'] as String?,
      fileSize: (json['fileSize'] as num?)?.toInt(),
      fileMime: json['fileMime'] as String?,
      remotePath: json['remotePath'] as String?,
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      nextAttemptMs: (json['nextAttemptMs'] as num?)?.toInt() ?? 0,
      status: json['status'] as String? ?? 'queued',
    );
  }
}

class OutgoingQueueService extends ChangeNotifier with WidgetsBindingObserver {
  OutgoingQueueService({
    required ChatService chatService,
    required StorageService storage,
    required SettingsService settings,
  })  : _chatService = chatService,
        _storage = storage,
        _settings = settings;

  static const _prefsPrefix = 'outgoing_queue_v1_';

  String get _prefsKey => '$_prefsPrefix${_uid ?? 'none'}';

  final ChatService _chatService;
  final StorageService _storage;
  final SettingsService _settings;
  final List<OutgoingJob> _jobs = [];
  String? _uid;
  String? lastError;
  bool _pumping = false;
  bool _observing = false;
  String? _activeId;
  Timer? _retry;

  String? get activeJobId => _activeId;

  List<OutgoingJob> get jobs => List.unmodifiable(_jobs);

  List<OutgoingJob> jobsFor({required String chatId, String? pendingEmail}) {
    final email = (pendingEmail ?? '').trim().toLowerCase();
    return _jobs.where((job) {
      if (chatId.isNotEmpty) return job.chatId == chatId;
      if (email.isEmpty) return false;
      return job.chatId.isEmpty && job.pendingEmail == email;
    }).toList();
  }

  Future<void> bind(String uid) async {
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    if (_uid == uid) {
      unawaited(pump());
      return;
    }
    _uid = uid;
    await load();
    _jobs.removeWhere((job) => job.senderId != uid);
    await _persist();
    unawaited(pump());
  }

  void clearError() {
    lastError = null;
  }

  void unbind() {
    _uid = null;
    _retry?.cancel();
    _retry = null;
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive) {
      unawaited(pump());
    }
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    _jobs
      ..clear()
      ..addAll(_decode(raw));
    notifyListeners();
  }

  Future<void> enqueueText({
    required String senderId,
    required String text,
    required String chatId,
    String pendingEmail = '',
    ChatMessage? replyTo,
    int? expireSeconds,
  }) async {
    final now = DateTime.now();
    final job = OutgoingJob(
      id: 'local-${now.microsecondsSinceEpoch}',
      senderId: senderId,
      createdAtMs: now.millisecondsSinceEpoch,
      text: text,
      type: MessageType.text,
      chatId: chatId,
      pendingEmail: pendingEmail.trim().toLowerCase(),
      replyToId: replyTo?.id,
      replyToText: replyTo?.preview,
      replyToSenderId: replyTo?.senderId,
      expireSeconds: expireSeconds,
    );
    _jobs.add(job);
    await _persist();
    notifyListeners();
    unawaited(pump());
  }

  Future<void> enqueueMedia({
    required String senderId,
    required String chatId,
    required File file,
    required MessageType type,
    required String contentType,
    String pendingEmail = '',
    ChatMessage? replyTo,
    int? expireSeconds,
    String? fileName,
    int? fileSize,
  }) async {
    final now = DateTime.now();
    final id = 'local-${now.microsecondsSinceEpoch}';
    final stored = await _stashFile(id, file, fileName);
    final job = OutgoingJob(
      id: id,
      senderId: senderId,
      createdAtMs: now.millisecondsSinceEpoch,
      text: ChatService.mediaLabel(type, fileName: fileName),
      type: type,
      chatId: chatId,
      pendingEmail: pendingEmail.trim().toLowerCase(),
      replyToId: replyTo?.id,
      replyToText: replyTo?.preview,
      replyToSenderId: replyTo?.senderId,
      expireSeconds: expireSeconds,
      localPath: stored,
      fileName: fileName,
      fileSize: fileSize ?? await file.length(),
      fileMime: contentType,
    );
    _jobs.add(job);
    await _persist();
    notifyListeners();
    unawaited(pump());
  }

  Future<void> complete(String id) async {
    final index = _jobs.indexWhere((job) => job.id == id);
    if (index < 0) return;
    final job = _jobs.removeAt(index);
    await _deleteStash(job.localPath);
    await _persist();
    notifyListeners();
  }

  Future<void> pump() async {
    if (_pumping) return;
    _pumping = true;
    _retry?.cancel();
    _retry = null;
    try {
      final touched = <String>{};
      while (_uid != null) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final index = _jobs.indexWhere(
          (job) => job.nextAttemptMs <= now && !touched.contains(job.id),
        );
        if (index < 0) break;
        final job = _jobs[index];
        touched.add(job.id);
        _activeId = job.id;
        _jobs[index] = job.copyWith(status: 'sending');
        notifyListeners();
        if (job.senderId != _uid) {
          await complete(job.id);
          continue;
        }
        try {
          await _send(job);
          await complete(job.id);
        } on ChatBlockedException {
          await complete(job.id);
        } catch (error) {
          debugPrint('HM_QUEUE_RETRY: $error');
          final current = _jobs.indexWhere((item) => item.id == job.id);
          if (current < 0) continue;
          final attempts = _jobs[current].attempts + 1;
          final kind = classifyOutgoingFailure(error);
          final giveUp =
              kind == OutgoingFailureKind.drop || (job.isMedia && attempts >= 5);
          if (giveUp) {
            lastError = _dropNotice(job, error);
            await complete(job.id);
            notifyListeners();
            continue;
          }
          final waitSec = attempts <= 2 ? 4 : 12;
          _jobs[current] = _jobs[current].copyWith(
            status: 'queued',
            attempts: attempts,
            nextAttemptMs:
                DateTime.now().millisecondsSinceEpoch + waitSec * 1000,
          );
          await _persist();
          if (attempts == 1) {
            lastError = job.isMedia
                ? 'Medya gönderilemedi. Bağlantı gelince tekrar denenecek.'
                : 'Mesaj gönderilemedi. Bağlantı gelince tekrar denenecek.';
          }
          notifyListeners();
        }
      }
      _armRetry();
    } finally {
      _activeId = null;
      _pumping = false;
      notifyListeners();
      final now = DateTime.now().millisecondsSinceEpoch;
      if (_uid != null && _jobs.any((job) => job.nextAttemptMs <= now)) {
        unawaited(pump());
      }
    }
  }

  void _armRetry() {
    final now = DateTime.now().millisecondsSinceEpoch;
    int? soonest;
    for (final job in _jobs) {
      if (job.nextAttemptMs <= now) continue;
      if (soonest == null || job.nextAttemptMs < soonest) {
        soonest = job.nextAttemptMs;
      }
    }
    if (soonest == null) return;
    final waitMs = (soonest - now).clamp(500, 30000);
    _retry = Timer(
      Duration(milliseconds: waitMs),
      () => unawaited(pump()),
    );
  }

  String _dropNotice(OutgoingJob job, Object error) {
    final raw = error.toString();
    if (error is FileSystemException) {
      return 'Dosya bulunamadı, gönderilemedi.';
    }
    if (error is MediaUploadException && raw.contains('75 MB')) return raw;
    if (job.isMedia) return 'Medya gönderilemedi.';
    return 'Mesaj sunucuya yazılamadı.';
  }

  Future<void> _send(OutgoingJob job) async {
    ChatMessage? reply;
    if ((job.replyToId ?? '').isNotEmpty &&
        !(job.replyToId ?? '').startsWith('local-')) {
      reply = ChatMessage(
        id: job.replyToId!,
        senderId: job.replyToSenderId ?? '',
        text: job.replyToText ?? '',
        createdAt: null,
        readBy: const [],
      );
    }
    if (!job.isMedia) {
      if (job.isPendingEmail) {
        await _chatService.sendPendingText(
          senderId: job.senderId,
          recipientEmail: job.pendingEmail,
          text: job.text,
          replyTo: reply,
          expireSeconds: job.expireSeconds,
        );
      } else {
        await _chatService.sendTextMessage(
          chatId: job.chatId,
          senderId: job.senderId,
          text: job.text,
          replyTo: reply,
          expireSeconds: job.expireSeconds,
        );
      }
      return;
    }
    final live = _liveJob(job);
    final path = live.localPath;
    if (path == null || path.isEmpty) {
      throw const FileSystemException('Kuyruk dosyası yok.');
    }
    final file = File(path);
    if (!file.existsSync()) {
      throw const FileSystemException('Kuyruk dosyası silinmiş.');
    }
    final folder = live.chatId.isNotEmpty
        ? 'chat_media/${live.chatId}'
        : 'pending_media/${ChatService.emailKey(live.pendingEmail.isEmpty ? live.senderId : live.pendingEmail)}';
    String? cachedPath;
    try {
      cachedPath = (await _storage.persistChatFile(
        id: live.id,
        file: file,
        fileName: live.fileName,
      )).path;
    } catch (_) {}
    final existing = (live.remotePath ?? '').trim();
    final url = existing.isNotEmpty
        ? existing
        : await _storage.uploadChatMedia(
            folder: folder,
            file: file,
            contentType: live.fileMime ?? 'application/octet-stream',
            fileName: live.fileName,
            ownerId: live.senderId,
          );
    _rememberRemote(live.id, url);
    if (cachedPath != null) {
      try {
        await _settings.rememberMediaFile([live.id, url], cachedPath);
      } catch (_) {}
    }
    final size = job.fileSize ?? await file.length();
    if (job.isPendingEmail) {
      await _chatService.sendPendingMedia(
        senderId: job.senderId,
        recipientEmail: job.pendingEmail,
        mediaUrl: url,
        type: job.type,
        replyTo: reply,
        expireSeconds: job.expireSeconds,
        fileName: job.fileName,
        fileSize: size,
        fileMime: job.fileMime,
      );
    } else {
      await _chatService.sendMediaMessage(
        chatId: job.chatId,
        senderId: job.senderId,
        mediaUrl: url,
        type: job.type,
        replyTo: reply,
        expireSeconds: job.expireSeconds,
        fileName: job.fileName,
        fileSize: size,
        fileMime: job.fileMime,
      );
    }
  }

  Future<String> _stashFile(String id, File file, String? fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory(p.join(dir.path, 'outgoing'));
    if (!folder.existsSync()) {
      await folder.create(recursive: true);
    }
    final ext = p.extension(fileName ?? file.path);
    final dest = File(p.join(folder.path, '$id$ext'));
    if (file.path != dest.path) {
      try {
        await file.copy(dest.path);
      } catch (_) {
        await dest.writeAsBytes(await file.readAsBytes());
      }
    }
    if (!dest.existsSync() || await dest.length() <= 0) {
      throw const FileSystemException('Medya kopyalanamadı.');
    }
    return dest.path;
  }

  OutgoingJob _liveJob(OutgoingJob job) {
    final index = _jobs.indexWhere((item) => item.id == job.id);
    if (index < 0) return job;
    return _jobs[index];
  }

  void _rememberRemote(String id, String url) {
    final index = _jobs.indexWhere((item) => item.id == id);
    if (index < 0 || url.isEmpty) return;
    if (_jobs[index].remotePath == url) return;
    _jobs[index] = _jobs[index].copyWith(remotePath: url);
    unawaited(_persist());
  }

  Future<void> _deleteStash(String? path) async {
    if (path == null || path.isEmpty) return;
    if (!path.contains('${p.separator}outgoing${p.separator}')) return;
    try {
      final file = File(path);
      if (file.existsSync()) await file.delete();
    } catch (_) {}
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(_jobs.map((job) => job.toJson()).toList()),
    );
  }

  List<OutgoingJob> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [
        for (final item in list)
          if (item is Map)
            OutgoingJob.fromJson(Map<String, dynamic>.from(item)),
      ].where((job) => job.id.isNotEmpty).toList();
    } catch (_) {
      return const [];
    }
  }
}

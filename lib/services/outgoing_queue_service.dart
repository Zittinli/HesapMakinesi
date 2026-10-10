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

  OutgoingJob copyWith({String? status, String? localPath, int? fileSize}) {
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
    try {
      while (_uid != null) {
        final index = _jobs.indexWhere((job) => job.status != 'sent');
        if (index < 0) return;
        var job = _jobs[index];
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
        } on FileSystemException {
          await complete(job.id);
        } catch (error) {
          debugPrint('HM_QUEUE_RETRY: $error');
          final raw = error.toString();
          final denied = raw.contains('permission-denied') ||
              raw.contains('PERMISSION_DENIED');
          if (denied) {
            lastError = 'Mesaj sunucuya yazılamadı.';
            await complete(job.id);
            notifyListeners();
            continue;
          }
          if (index < _jobs.length && _jobs[index].id == job.id) {
            _jobs[index] = _jobs[index].copyWith(status: 'queued');
            await _persist();
            notifyListeners();
          }
          lastError = 'Mesaj gönderilemedi. Bağlantı gelince tekrar denenecek.';
          notifyListeners();
          _activeId = null;
          _retry?.cancel();
          _retry = Timer(const Duration(seconds: 4), () => unawaited(pump()));
          return;
        }
      }
    } finally {
      _activeId = null;
      _pumping = false;
      notifyListeners();
    }
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
    final path = job.localPath;
    if (path == null || path.isEmpty) {
      throw const FileSystemException('Kuyruk dosyası yok.');
    }
    final file = File(path);
    if (!file.existsSync()) {
      throw const FileSystemException('Kuyruk dosyası silinmiş.');
    }
    final folder = job.chatId.isNotEmpty
        ? 'chat_media/${job.chatId}'
        : 'pending_media/${ChatService.emailKey(job.pendingEmail.isEmpty ? job.senderId : job.pendingEmail)}';
    String? cachedPath;
    try {
      cachedPath = (await _storage.persistChatFile(
        id: job.id,
        file: file,
        fileName: job.fileName,
      )).path;
    } catch (_) {}
    final url = await _storage.uploadChatMedia(
      folder: folder,
      file: file,
      contentType: job.fileMime ?? 'application/octet-stream',
      fileName: job.fileName,
      ownerId: job.senderId,
    );
    if (cachedPath != null) {
      try {
        await _settings.rememberMediaFile([job.id, url], cachedPath);
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
    try {
      await file.copy(dest.path);
      return dest.path;
    } catch (_) {
      return file.path;
    }
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

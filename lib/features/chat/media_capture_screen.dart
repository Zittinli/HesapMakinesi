import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

class CapturedMedia {
  const CapturedMedia({
    required this.file,
    required this.isVideo,
    required this.contentType,
  });

  final File file;
  final bool isVideo;
  final String contentType;
}

class MediaCaptureScreen extends StatefulWidget {
  const MediaCaptureScreen({super.key});

  @override
  State<MediaCaptureScreen> createState() => _MediaCaptureScreenState();
}

class _MediaCaptureScreenState extends State<MediaCaptureScreen> {
  CameraController? _controller;
  Future<void>? _ready;
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;
  bool _videoMode = false;
  bool _recording = false;
  bool _recordPaused = false;
  bool _switchingCamera = false;
  bool _processing = false;
  bool _torchOn = false;
  CapturedMedia? _preview;
  VideoPlayerController? _video;
  String? _error;
  DateTime? _recordAnchor;
  Duration _recordAccumulated = Duration.zero;
  Timer? _recordTimer;
  int _previewEpoch = 0;
  final List<File> _videoSegments = [];
  static const _concatChannel = MethodChannel(
    'com.hesapmakinesi.hesap_makinesi/video_concat',
  );

  @override
  void initState() {
    super.initState();
    _ready = _openCamera();
  }

  Future<void> _openCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _error = 'Kamera bulunamadı.');
        return;
      }
      _cameraIndex = _cameras.indexWhere(
        (item) => item.lensDirection == CameraLensDirection.back,
      );
      if (_cameraIndex < 0) _cameraIndex = 0;
      await _initializeCamera(_cameras[_cameraIndex]);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Kamera açılamadı.');
      }
    }
  }

  void _onCameraChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _initializeCamera(CameraDescription description) async {
    final previous = _controller;
    previous?.removeListener(_onCameraChanged);
    if (previous != null) {
      if (mounted) setState(() => _controller = null);
      await previous.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 280));
    }
    final controller = CameraController(
      description,
      _videoMode ? ResolutionPreset.medium : ResolutionPreset.high,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      if (controller.value.isPreviewPaused) {
        await controller.resumePreview();
      }
      controller.addListener(_onCameraChanged);
      setState(() {
        _controller = controller;
        _previewEpoch++;
      });
      await _waitForPreviewFrame();
      if (controller.value.isPreviewPaused) {
        await controller.resumePreview();
      }
      if (_torchOn) {
        try {
          await controller.setFlashMode(FlashMode.torch);
        } catch (_) {
          _torchOn = false;
        }
      }
    } catch (error) {
      await controller.dispose();
      if (mounted) {
        setState(() => _error = 'Kamera açılamadı.');
      }
    }
  }

  Future<void> _waitForPreviewFrame() async {
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }

  Duration get _recordElapsed {
    if (_recordAnchor == null) return _recordAccumulated;
    return _recordAccumulated + DateTime.now().difference(_recordAnchor!);
  }

  void _startRecordTimer() {
    _recordAnchor = DateTime.now();
    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
  }

  void _pauseRecordTimer() {
    if (_recordAnchor != null) {
      _recordAccumulated += DateTime.now().difference(_recordAnchor!);
      _recordAnchor = null;
    }
    _recordTimer?.cancel();
    _recordTimer = null;
  }

  void _resetRecordTimer() {
    _pauseRecordTimer();
    _recordAccumulated = Duration.zero;
  }

  CameraDescription? _peerCamera(CameraDescription current) {
    final want = current.lensDirection == CameraLensDirection.front
        ? CameraLensDirection.back
        : CameraLensDirection.front;
    for (final item in _cameras) {
      if (item.lensDirection == want) return item;
    }
    return null;
  }

  Future<void> _switchCamera() async {
    if (_switchingCamera) return;
    final camera = _controller;
    if (camera == null || !camera.value.isInitialized) return;
    final next = _peerCamera(camera.value.description);
    if (next == null) return;

    setState(() => _switchingCamera = true);
    try {
      if (_recording && camera.value.isRecordingVideo) {
        final clip = await camera.stopVideoRecording();
        _videoSegments.add(await _moveToTemp(clip, '.mp4'));
      }
      _pauseRecordTimer();
      await _initializeCamera(next);
      if (!mounted) return;
      final nextCamera = _controller;
      if (_recording && nextCamera != null && nextCamera.value.isInitialized) {
        await nextCamera.startVideoRecording();
        _recordPaused = false;
        _startRecordTimer();
      }
      _cameraIndex = _cameras.indexWhere((item) => item.name == next.name);
      if (_cameraIndex < 0) {
        _cameraIndex = _cameras.indexWhere(
          (item) => item.lensDirection == next.lensDirection,
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Kamera cevrilemedi.')));
      }
    } finally {
      if (mounted) setState(() => _switchingCamera = false);
    }
  }

  Future<void> _toggleMediaMode() async {
    if (_recording || _switchingCamera || _cameras.isEmpty) return;
    setState(() {
      _switchingCamera = true;
      _videoMode = !_videoMode;
    });
    await _initializeCamera(_cameras[_cameraIndex]);
    if (mounted) setState(() => _switchingCamera = false);
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _controller?.removeListener(_onCameraChanged);
    _controller?.dispose();
    _video?.removeListener(_onPreviewVideoChanged);
    _video?.dispose();
    _videoSegments.clear();
    super.dispose();
  }

  Future<File> _joinVideoSegments(File last) async {
    final parts = [..._videoSegments, last];
    _videoSegments.clear();
    if (parts.length == 1 || !Platform.isAndroid) {
      return last;
    }
    try {
      final dest = File(
        p.join(
          (await getTemporaryDirectory()).path,
          'hm_${DateTime.now().millisecondsSinceEpoch}.mp4',
        ),
      );
      final path = await _concatChannel.invokeMethod<String>('concat', {
        'inputs': parts.map((file) => file.path).toList(),
        'output': dest.path,
      });
      if (path == null || path.isEmpty) return last;
      return File(path);
    } catch (_) {
      return last;
    }
  }

  Future<File> _moveToTemp(XFile raw, String fallbackExt) async {
    final dir = await getTemporaryDirectory();
    final ext = p.extension(raw.path).isEmpty
        ? fallbackExt
        : p.extension(raw.path);
    final dest = File(
      p.join(dir.path, 'hm_${DateTime.now().millisecondsSinceEpoch}$ext'),
    );
    return File(raw.path).copy(dest.path);
  }

  Future<void> _takePhoto() async {
    final camera = _controller;
    if (camera == null || !camera.value.isInitialized || _recording) return;
    try {
      final shot = await camera.takePicture();
      final file = await _moveToTemp(shot, '.jpg');
      setState(() {
        _preview = CapturedMedia(
          file: file,
          isVideo: false,
          contentType: 'image/jpeg',
        );
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Fotoğraf cekilemedi.')));
      }
    }
  }

  Future<void> _toggleRecord() async {
    final camera = _controller;
    if (camera == null || !camera.value.isInitialized) return;
    try {
      if (_recording) {
        setState(() => _processing = true);
        File? last;
        if (camera.value.isRecordingVideo) {
          last = await _moveToTemp(await camera.stopVideoRecording(), '.mp4');
        }
        _resetRecordTimer();
        final file = last != null
            ? await _joinVideoSegments(last)
            : await _joinExistingSegments();
        if (file == null) {
          setState(() {
            _recording = false;
            _recordPaused = false;
            _processing = false;
          });
          return;
        }
        final player = VideoPlayerController.file(file);
        player.addListener(_onPreviewVideoChanged);
        await player.initialize();
        await player.setLooping(true);
        await player.play();
        setState(() {
          _recording = false;
          _recordPaused = false;
          _torchOn = false;
          _video = player;
          _preview = CapturedMedia(
            file: file,
            isVideo: true,
            contentType: 'video/mp4',
          );
          _processing = false;
        });
      } else {
        _videoSegments.clear();
        _resetRecordTimer();
        await camera.startVideoRecording();
        _startRecordTimer();
        setState(() {
          _recording = true;
          _recordPaused = false;
        });
      }
    } catch (_) {
      if (mounted) {
        _resetRecordTimer();
        setState(() {
          _recording = false;
          _recordPaused = false;
          _processing = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Video kaydedilemedi.')));
      }
    }
  }

  Future<File?> _joinExistingSegments() async {
    if (_videoSegments.isEmpty) return null;
    final last = _videoSegments.removeLast();
    return _joinVideoSegments(last);
  }

  Future<void> _togglePauseRecord() async {
    final camera = _controller;
    if (camera == null || !_recording) return;
    try {
      if (_recordPaused) {
        if (camera.value.isRecordingVideo) {
          await camera.resumeVideoRecording();
        } else {
          await camera.startVideoRecording();
        }
        _startRecordTimer();
        setState(() => _recordPaused = false);
        return;
      }
      try {
        await camera.pauseVideoRecording();
      } catch (_) {
        final clip = await camera.stopVideoRecording();
        _videoSegments.add(await _moveToTemp(clip, '.mp4'));
      }
      _pauseRecordTimer();
      setState(() => _recordPaused = true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kayıt duraklatilamadi.')),
        );
      }
    }
  }

  Future<void> _toggleTorch() async {
    final camera = _controller;
    if (camera == null || !camera.value.isInitialized) return;
    final next = !_torchOn;
    try {
      await camera.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      setState(() => _torchOn = next);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Fener açılamadı.')));
      }
    }
  }

  void _onPreviewVideoChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _togglePreviewPlay() async {
    final video = _video;
    if (video == null) return;
    if (video.value.isPlaying) {
      await video.pause();
    } else {
      if (video.value.position >= video.value.duration) {
        await video.seekTo(Duration.zero);
      }
      await video.play();
    }
    if (mounted) setState(() {});
  }

  Future<void> _seekPreviewBy(Duration offset) async {
    final video = _video;
    if (video == null) return;
    final targetMs = (video.value.position + offset).inMilliseconds
        .clamp(0, video.value.duration.inMilliseconds)
        .toInt();
    await video.seekTo(Duration(milliseconds: targetMs));
  }

  Future<void> _restartPreview() async {
    final video = _video;
    if (video == null) return;
    await video.seekTo(Duration.zero);
    await video.play();
  }

  Future<void> _togglePreviewMute() async {
    final video = _video;
    if (video == null) return;
    await video.setVolume(video.value.volume == 0 ? 1 : 0);
  }

  String _formatDuration(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  Future<void> _pickFromGallery() async {
    try {
      final picker = ImagePicker();
      final raw = _videoMode
          ? await picker.pickVideo(source: ImageSource.gallery)
          : await picker.pickImage(
              source: ImageSource.gallery,
              imageQuality: 85,
            );
      if (raw == null) return;
      final file = await _moveToTemp(raw, _videoMode ? '.mp4' : '.jpg');
      VideoPlayerController? player;
      if (_videoMode) {
        player = VideoPlayerController.file(file);
        player.addListener(_onPreviewVideoChanged);
        await player.initialize();
        await player.setLooping(true);
        await player.play();
      }
      _video?.removeListener(_onPreviewVideoChanged);
      _video?.dispose();
      setState(() {
        _video = player;
        _preview = CapturedMedia(
          file: file,
          isVideo: _videoMode,
          contentType: _videoMode ? 'video/mp4' : 'image/jpeg',
        );
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Galeri açılamadı.')));
    }
  }

  void _retake() {
    _video?.removeListener(_onPreviewVideoChanged);
    _video?.dispose();
    _videoSegments.clear();
    _resetRecordTimer();
    setState(() {
      _video = null;
      _preview = null;
      _recording = false;
      _recordPaused = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white70,
        title: Text(
          _recording
              ? _formatDuration(_recordElapsed)
              : (_videoMode ? 'Video' : 'Fotoğraf'),
        ),
        actions: [
          TextButton(
            onPressed: (_recording || _switchingCamera)
                ? null
                : _toggleMediaMode,
            child: Text(
              _videoMode ? 'Fotoğrafa gec' : 'Videoya gec',
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
      body: _preview != null ? _buildPreview() : _buildCamera(),
    );
  }

  Widget _buildCamera() {
    return FutureBuilder<void>(
      future: _ready,
      builder: (context, snapshot) {
        final camera = _controller;
        if (_error != null) {
          return Center(
            child: Text(_error!, style: const TextStyle(color: Colors.white70)),
          );
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            if (camera != null && camera.value.isInitialized)
              _livePreview(camera)
            else
              const ColoredBox(color: Colors.black),
            if (camera == null ||
                !camera.value.isInitialized ||
                _switchingCamera ||
                _processing)
              const ColoredBox(
                color: Color(0x99000000),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.white70),
                      SizedBox(height: 12),
                      Text(
                        'Hazırlanıyor...',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            if (_recording)
              SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _recordingBadge(),
                  ),
                ),
              ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_videoMode) _recordingControls(),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          tooltip: 'Galeriden seç',
                          onPressed: (_recording || _switchingCamera)
                              ? null
                              : _pickFromGallery,
                          icon: const Icon(
                            Icons.photo_library_outlined,
                            color: Colors.white70,
                          ),
                        ),
                        GestureDetector(
                          onTap: _switchingCamera
                              ? null
                              : (_videoMode ? _toggleRecord : _takePhoto),
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 4),
                              color: _recording
                                  ? const Color(0xFFFF5252)
                                  : Colors.white24,
                            ),
                            child: _recording
                                ? const Icon(Icons.stop, color: Colors.white)
                                : null,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Kamerayı çevir',
                          onPressed: _cameras.length > 1 && !_switchingCamera
                              ? _switchCamera
                              : null,
                          icon: _switchingCamera
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white70,
                                  ),
                                )
                              : const Icon(
                                  Icons.cameraswitch_outlined,
                                  color: Colors.white70,
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _livePreview(CameraController camera) {
    final previewSize = camera.value.previewSize;
    final preview = CameraPreview(
      camera,
      key: ValueKey(
        '${camera.description.name}_${camera.description.lensDirection}_$_previewEpoch',
      ),
    );
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black,
        child: previewSize == null
            ? preview
            : FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: previewSize.height,
                  height: previewSize.width,
                  child: preview,
                ),
              ),
      ),
    );
  }

  Widget _recordingBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xCC000000),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _recordPaused
                  ? Colors.amber
                  : const Color(0xFFFF5252),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _recordPaused
                ? 'Duraklatildi  ${_formatDuration(_recordElapsed)}'
                : _formatDuration(_recordElapsed),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _recordingControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton.filledTonal(
          tooltip: _torchOn ? 'Feneri kapat' : 'Feneri aç',
          onPressed: _switchingCamera ? null : _toggleTorch,
          style: IconButton.styleFrom(
            backgroundColor: _torchOn
                ? const Color(0xFFFFC107)
                : const Color(0x66000000),
            foregroundColor: _torchOn ? Colors.black : Colors.white,
          ),
          icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
        ),
        if (_recording) ...[
          const SizedBox(width: 12),
          IconButton.filledTonal(
            tooltip: _recordPaused ? 'Devam et' : 'Duraklat',
            onPressed: _switchingCamera ? null : _togglePauseRecord,
            style: IconButton.styleFrom(
              backgroundColor: const Color(0x66000000),
              foregroundColor: Colors.white,
            ),
            icon: Icon(_recordPaused ? Icons.play_arrow : Icons.pause),
          ),
        ],
      ],
    );
  }

  Widget _buildPreview() {
    final media = _preview!;
    final video = _video;
    return Column(
      children: [
        Expanded(
          child: media.isVideo
              ? (video == null || !video.value.isInitialized
                    ? const Center(child: CircularProgressIndicator())
                    : _buildCaptureVideo(video))
              : Image.file(media.file, fit: BoxFit.contain),
        ),
        if (media.isVideo && video != null && video.value.isInitialized)
          _buildCaptureVideoBar(video),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _retake,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                      ),
                      child: const Text('Yeniden'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, media),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2A2A2A),
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Gönder'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCaptureVideo(VideoPlayerController video) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _togglePreviewPlay,
      onDoubleTapDown: (details) {
        final width = MediaQuery.sizeOf(context).width;
        if (details.globalPosition.dx < width / 2) {
          _seekPreviewBy(const Duration(seconds: -5));
        } else {
          _seekPreviewBy(const Duration(seconds: 5));
        }
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: video.value.aspectRatio == 0
                  ? 9 / 16
                  : video.value.aspectRatio,
              child: VideoPlayer(video),
            ),
          ),
          if (!video.value.isPlaying)
            const Icon(
              Icons.play_circle_fill,
              color: Colors.white70,
              size: 72,
            ),
        ],
      ),
    );
  }

  Widget _buildCaptureVideoBar(VideoPlayerController video) {
    final durationMs = video.value.duration.inMilliseconds;
    final positionMs = video.value.position.inMilliseconds.clamp(0, durationMs);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white30,
              thumbColor: Colors.white,
              overlayColor: Colors.white12,
            ),
            child: Slider(
              min: 0,
              max: durationMs <= 0 ? 1 : durationMs.toDouble(),
              value: durationMs <= 0 ? 0 : positionMs.toDouble(),
              onChanged: (value) {
                video.seekTo(Duration(milliseconds: value.round()));
              },
            ),
          ),
          Row(
            children: [
              IconButton(
                tooltip: '5 saniye geri',
                onPressed: () => _seekPreviewBy(const Duration(seconds: -5)),
                icon: const Icon(Icons.replay_5, color: Colors.white70),
              ),
              IconButton(
                tooltip: video.value.isPlaying ? 'Duraklat' : 'Oynat',
                onPressed: _togglePreviewPlay,
                icon: Icon(
                  video.value.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                ),
              ),
              IconButton(
                tooltip: 'Başa sar',
                onPressed: _restartPreview,
                icon: const Icon(Icons.restart_alt, color: Colors.white70),
              ),
              IconButton(
                tooltip: '5 saniye ileri',
                onPressed: () => _seekPreviewBy(const Duration(seconds: 5)),
                icon: const Icon(Icons.forward_5, color: Colors.white70),
              ),
              Text(
                '${_formatDuration(video.value.position)} / '
                '${_formatDuration(video.value.duration)}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const Spacer(),
              IconButton(
                tooltip: video.value.volume == 0 ? 'Sesi aç' : 'Sessize al',
                onPressed: _togglePreviewMute,
                icon: Icon(
                  video.value.volume == 0 ? Icons.volume_off : Icons.volume_up,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

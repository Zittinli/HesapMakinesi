import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
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
  bool _switchingCamera = false;
  CapturedMedia? _preview;
  VideoPlayerController? _video;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ready = _openCamera();
  }

  Future<void> _openCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _error = 'Kamera bulunamadi.');
        return;
      }
      _cameraIndex = _cameras.indexWhere(
        (item) => item.lensDirection == CameraLensDirection.back,
      );
      if (_cameraIndex < 0) _cameraIndex = 0;
      await _initializeCamera(_cameras[_cameraIndex]);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Kamera acilamadi.');
      }
    }
  }

  Future<void> _initializeCamera(CameraDescription description) async {
    final previous = _controller;
    final controller = CameraController(
      description,
      _videoMode ? ResolutionPreset.medium : ResolutionPreset.high,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _controller = controller;
    await previous?.dispose();
    try {
      await controller.initialize();
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Kamera acilamadi.');
      }
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _recording || _switchingCamera) return;
    setState(() => _switchingCamera = true);
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _initializeCamera(_cameras[_cameraIndex]);
    if (mounted) setState(() => _switchingCamera = false);
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
    _controller?.dispose();
    _video?.dispose();
    super.dispose();
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
        ).showSnackBar(const SnackBar(content: Text('Fotograf cekilemedi.')));
      }
    }
  }

  Future<void> _toggleRecord() async {
    final camera = _controller;
    if (camera == null || !camera.value.isInitialized) return;
    try {
      if (_recording) {
        final raw = await camera.stopVideoRecording();
        final file = await _moveToTemp(raw, '.mp4');
        final player = VideoPlayerController.file(file);
        await player.initialize();
        await player.setLooping(true);
        await player.play();
        setState(() {
          _recording = false;
          _video = player;
          _preview = CapturedMedia(
            file: file,
            isVideo: true,
            contentType: 'video/mp4',
          );
        });
      } else {
        await camera.startVideoRecording();
        setState(() => _recording = true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _recording = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Video kaydedilemedi.')));
      }
    }
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
        await player.initialize();
        await player.setLooping(true);
        await player.play();
      }
      setState(() {
        _video?.dispose();
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
      ).showSnackBar(const SnackBar(content: Text('Galeri acilamadi.')));
    }
  }

  void _retake() {
    _video?.dispose();
    setState(() {
      _video = null;
      _preview = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white70,
        title: Text(_videoMode ? 'Video' : 'Fotograf'),
        actions: [
          TextButton(
            onPressed: (_recording || _switchingCamera)
                ? null
                : _toggleMediaMode,
            child: Text(
              _videoMode ? 'Fotografa gec' : 'Videoya gec',
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
        if (camera == null || !camera.value.isInitialized) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white24),
          );
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            CameraPreview(camera),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      tooltip: 'Galeriden sec (istege bagli)',
                      onPressed: _pickFromGallery,
                      icon: const Icon(
                        Icons.photo_library_outlined,
                        color: Colors.white70,
                      ),
                    ),
                    GestureDetector(
                      onTap: _videoMode ? _toggleRecord : _takePhoto,
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
                      ),
                    ),
                    IconButton(
                      tooltip: 'Kamerayi cevir',
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
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPreview() {
    final media = _preview!;
    return Column(
      children: [
        Expanded(
          child: media.isVideo
              ? (_video == null
                    ? const Center(child: CircularProgressIndicator())
                    : AspectRatio(
                        aspectRatio: _video!.value.aspectRatio == 0
                            ? 9 / 16
                            : _video!.value.aspectRatio,
                        child: VideoPlayer(_video!),
                      ))
              : Image.file(media.file, fit: BoxFit.contain),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
          child: Column(
            children: [
              const Text(
                'Cekim uygulamada kalir. Galeriye yazilmaz.',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
              const SizedBox(height: 12),
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
                      child: const Text('Gonder'),
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
}

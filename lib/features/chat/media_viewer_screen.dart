import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

class MediaViewerScreen extends StatefulWidget {
  const MediaViewerScreen({
    super.key,
    required this.url,
    required this.isVideo,
  });

  final String url;
  final bool isVideo;

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen>
    with WidgetsBindingObserver {
  VideoPlayerController? _video;
  Timer? _controlsTimer;
  String? _error;
  bool _showControls = true;
  bool _isFullscreen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.isVideo) {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
      );
      _video = controller;
      controller.addListener(_onVideoChanged);
      controller
          .initialize()
          .then((_) async {
            if (!mounted) return;
            await controller.play();
            _scheduleControlsHide();
            setState(() {});
          })
          .catchError((_) {
            if (mounted) setState(() => _error = 'Video acilamadi.');
          });
    }
  }

  void _onVideoChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _video?.pause();
      _controlsTimer?.cancel();
      if (mounted) setState(() => _showControls = true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controlsTimer?.cancel();
    _video
      ?..removeListener(_onVideoChanged)
      ..dispose();
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]);
    }
    super.dispose();
  }

  void _scheduleControlsHide() {
    _controlsTimer?.cancel();
    if (_video?.value.isPlaying != true) return;
    _controlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleControlsHide();
  }

  Future<void> _togglePlay() async {
    final video = _video;
    if (video == null) return;
    if (video.value.isPlaying) {
      await video.pause();
      _controlsTimer?.cancel();
      if (mounted) setState(() => _showControls = true);
      return;
    }
    if (video.value.position >= video.value.duration) {
      await video.seekTo(Duration.zero);
    }
    await video.play();
    _scheduleControlsHide();
  }

  Future<void> _seekBy(Duration offset) async {
    final video = _video;
    if (video == null) return;
    final targetMs = (video.value.position + offset).inMilliseconds
        .clamp(0, video.value.duration.inMilliseconds)
        .toInt();
    await video.seekTo(Duration(milliseconds: targetMs));
    _scheduleControlsHide();
  }

  Future<void> _toggleMute() async {
    final video = _video;
    if (video == null) return;
    await video.setVolume(video.value.volume == 0 ? 1 : 0);
    _scheduleControlsHide();
  }

  Future<void> _toggleFullscreen() async {
    if (_isFullscreen) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    if (mounted) setState(() => _isFullscreen = !_isFullscreen);
    _scheduleControlsHide();
  }

  String _formatDuration(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isVideo) {
      return Scaffold(backgroundColor: Colors.black, body: _buildVideo());
    }
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white70,
        title: const Text('Fotograf'),
      ),
      body: Center(child: _buildImage()),
    );
  }

  Widget _buildImage() {
    return InteractiveViewer(
      minScale: 0.8,
      maxScale: 5,
      child: CachedNetworkImage(
        imageUrl: widget.url,
        fit: BoxFit.contain,
        placeholder: (_, __) =>
            const CircularProgressIndicator(color: Colors.white24),
        errorWidget: (_, __, ___) => const Text(
          'Fotograf acilamadi.',
          style: TextStyle(color: Colors.white54),
        ),
      ),
    );
  }

  Widget _buildVideo() {
    if (_error != null) {
      return SafeArea(
        child: Stack(
          children: [
            Center(
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.white54),
              ),
            ),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back, color: Colors.white),
            ),
          ],
        ),
      );
    }
    final video = _video;
    if (video == null || !video.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white24),
      );
    }

    final durationMs = video.value.duration.inMilliseconds;
    final positionMs = video.value.position.inMilliseconds.clamp(0, durationMs);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleControls,
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
          if (video.value.isBuffering)
            const CircularProgressIndicator(color: Colors.white70),
          IgnorePointer(
            ignoring: !_showControls,
            child: AnimatedOpacity(
              opacity: _showControls ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: Stack(
                children: [
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0x99000000),
                            Color(0x22000000),
                            Color(0xAA000000),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SafeArea(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: IconButton(
                        tooltip: 'Geri',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                    ),
                  ),
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: '10 saniye geri',
                          iconSize: 36,
                          onPressed: () =>
                              _seekBy(const Duration(seconds: -10)),
                          icon: const Icon(
                            Icons.replay_10,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 20),
                        IconButton(
                          tooltip: video.value.isPlaying ? 'Duraklat' : 'Oynat',
                          iconSize: 62,
                          onPressed: _togglePlay,
                          icon: Icon(
                            video.value.isPlaying
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_fill,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 20),
                        IconButton(
                          tooltip: '10 saniye ileri',
                          iconSize: 36,
                          onPressed: () => _seekBy(const Duration(seconds: 10)),
                          icon: const Icon(
                            Icons.forward_10,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SafeArea(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 8, 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
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
                                max: durationMs <= 0
                                    ? 1
                                    : durationMs.toDouble(),
                                value: durationMs <= 0
                                    ? 0
                                    : positionMs.toDouble(),
                                onChanged: (value) {
                                  video.seekTo(
                                    Duration(milliseconds: value.round()),
                                  );
                                },
                                onChangeStart: (_) => _controlsTimer?.cancel(),
                                onChangeEnd: (_) => _scheduleControlsHide(),
                              ),
                            ),
                            Row(
                              children: [
                                Text(
                                  '${_formatDuration(video.value.position)} / '
                                  '${_formatDuration(video.value.duration)}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  tooltip: video.value.volume == 0
                                      ? 'Sesi ac'
                                      : 'Sessize al',
                                  onPressed: _toggleMute,
                                  icon: Icon(
                                    video.value.volume == 0
                                        ? Icons.volume_off
                                        : Icons.volume_up,
                                    color: Colors.white,
                                  ),
                                ),
                                PopupMenuButton<double>(
                                  tooltip: 'Oynatma hizi',
                                  color: const Color(0xFF202020),
                                  initialValue: video.value.playbackSpeed,
                                  onSelected: (speed) {
                                    video.setPlaybackSpeed(speed);
                                    _scheduleControlsHide();
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: 0.5,
                                      child: Text('0.5x'),
                                    ),
                                    PopupMenuItem(
                                      value: 1.0,
                                      child: Text('Normal'),
                                    ),
                                    PopupMenuItem(
                                      value: 1.5,
                                      child: Text('1.5x'),
                                    ),
                                    PopupMenuItem(
                                      value: 2.0,
                                      child: Text('2x'),
                                    ),
                                  ],
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 12,
                                    ),
                                    child: Text(
                                      '${video.value.playbackSpeed}x',
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: _isFullscreen
                                      ? 'Tam ekrandan cik'
                                      : 'Tam ekran',
                                  onPressed: _toggleFullscreen,
                                  icon: Icon(
                                    _isFullscreen
                                        ? Icons.fullscreen_exit
                                        : Icons.fullscreen,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

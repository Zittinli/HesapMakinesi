import 'package:flutter/material.dart';

enum _SwipeAim { reply, menu }

class ReplySwipe extends StatefulWidget {
  const ReplySwipe({
    super.key,
    required this.child,
    required this.onReply,
    required this.onMenu,
  });

  final Widget child;
  final VoidCallback onReply;
  final VoidCallback onMenu;

  @override
  State<ReplySwipe> createState() => _ReplySwipeState();
}

class _ReplySwipeState extends State<ReplySwipe>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double _drag = 0;
  double _from = 0;
  double _slop = 0;
  _SwipeAim? _aim;
  int _token = 0;

  static const _max = 72.0;
  static const _trigger = 46.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    )..addListener(() {
        setState(() => _drag = _from * (1 - _controller.value));
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _snapBack({required bool fire}) {
    final token = ++_token;
    final aim = _aim;
    _from = _drag;
    _controller
      ..duration = Duration(milliseconds: fire ? 320 : 240)
      ..forward(from: 0).whenComplete(() {
        if (!mounted || token != _token) return;
        _aim = null;
        if (!fire) return;
        if (aim == _SwipeAim.reply) widget.onReply();
        if (aim == _SwipeAim.menu) widget.onMenu();
      });
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_drag.abs() / _max).clamp(0.0, 1.0);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) {
        if (_controller.isAnimating) return;
        _aim = null;
        _slop = 0;
      },
      onHorizontalDragUpdate: (details) {
        if (_controller.isAnimating) return;
        final dx = details.delta.dx;
        if (_aim == null) {
          _slop += dx;
          if (_slop > 8) {
            _aim = _SwipeAim.reply;
          } else if (_slop < -8) {
            _aim = _SwipeAim.menu;
          } else {
            return;
          }
        }
        final next = _aim == _SwipeAim.reply
            ? (_drag + dx * 0.42).clamp(0.0, _max)
            : (_drag + dx * 0.42).clamp(-_max, 0.0);
        setState(() => _drag = next);
      },
      onHorizontalDragEnd: (_) {
        if (_controller.isAnimating) return;
        final fire = switch (_aim) {
          _SwipeAim.reply => _drag >= _trigger,
          _SwipeAim.menu => -_drag >= _trigger,
          null => false,
        };
        _snapBack(fire: fire);
      },
      onHorizontalDragCancel: () {
        if (_controller.isAnimating) return;
        _snapBack(fire: false);
      },
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          if (_drag > 0)
            Opacity(
              opacity: progress,
              child: const Padding(
                padding: EdgeInsets.only(left: 18),
                child: Icon(Icons.reply, color: Colors.white38, size: 20),
              ),
            ),
          if (_drag < 0)
            Positioned(
              right: 18,
              top: 0,
              bottom: 0,
              child: Opacity(
                opacity: progress,
                child: const Align(
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.more_horiz,
                    color: Colors.white38,
                    size: 20,
                  ),
                ),
              ),
            ),
          Transform.translate(
            offset: Offset(_drag, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

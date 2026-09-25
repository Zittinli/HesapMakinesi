import 'package:flutter/material.dart';

class ReplySwipe extends StatefulWidget {
  const ReplySwipe({
    super.key,
    required this.child,
    required this.onReply,
  });

  final Widget child;
  final VoidCallback onReply;

  @override
  State<ReplySwipe> createState() => _ReplySwipeState();
}

class _ReplySwipeState extends State<ReplySwipe>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double _drag = 0;

  static const _max = 72.0;
  static const _trigger = 46.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..addListener(() {
        setState(() => _drag = _controller.value * _max);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _snapBack({required bool reply}) {
    final from = (_drag / _max).clamp(0.0, 1.0);
    _controller.value = from;
    _controller
        .animateTo(
          0,
          duration: Duration(milliseconds: reply ? 320 : 240),
          curve: reply ? Curves.easeOutCubic : Curves.easeOutQuart,
        )
        .whenComplete(() {
          if (reply) widget.onReply();
        });
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_drag / _max).clamp(0.0, 1.0);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: (details) {
        if (_controller.isAnimating) return;
        final next = (_drag + details.delta.dx * 0.42).clamp(0.0, _max);
        setState(() => _drag = next);
      },
      onHorizontalDragEnd: (_) {
        if (_controller.isAnimating) return;
        _snapBack(reply: _drag >= _trigger);
      },
      onHorizontalDragCancel: () {
        if (_controller.isAnimating) return;
        _snapBack(reply: false);
      },
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Opacity(
            opacity: progress,
            child: const Padding(
              padding: EdgeInsets.only(left: 18),
              child: Icon(Icons.reply, color: Colors.white38, size: 20),
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

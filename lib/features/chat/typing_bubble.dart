import 'dart:math' as math;

import 'package:flutter/material.dart';

class TypingBubble extends StatefulWidget {
  const TypingBubble({super.key});

  @override
  State<TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<TypingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 980),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.55, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) {
        return Transform.scale(scale: scale, child: child);
      },
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            size: const Size(22, 18),
            painter: _CuteTypingPainter(t: _controller.value),
          );
        },
      ),
    );
  }
}

class _CuteTypingPainter extends CustomPainter {
  const _CuteTypingPainter({required this.t});

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = const Color(0xFF90CAF9)
      ..style = PaintingStyle.fill;
    final glow = Paint()
      ..color = const Color(0x6690CAF9)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.4);
    final highlight = Paint()
      ..color = const Color(0x55FFFFFF)
      ..style = PaintingStyle.fill;

    final left = 1.2;
    final top = 1.0;
    final right = size.width - 1.2;
    final bottom = size.height * 0.72;
    const r = 5.2;
    final tailTip = Offset(size.width * 0.18, size.height - 0.8);
    final tailLeft = Offset(size.width * 0.28, bottom);
    final tailRight = Offset(size.width * 0.52, bottom);

    final path = Path()
      ..moveTo(left + r, top)
      ..lineTo(right - r, top)
      ..quadraticBezierTo(right, top, right, top + r)
      ..lineTo(right, bottom - r)
      ..quadraticBezierTo(right, bottom, right - r, bottom)
      ..lineTo(tailRight.dx, tailRight.dy)
      ..lineTo(tailTip.dx, tailTip.dy)
      ..lineTo(tailLeft.dx, tailLeft.dy)
      ..lineTo(left + r, bottom)
      ..quadraticBezierTo(left, bottom, left, bottom - r)
      ..lineTo(left, top + r)
      ..quadraticBezierTo(left, top, left + r, top)
      ..close();

    canvas.drawPath(path, glow);
    canvas.drawPath(path, fill);

    final shine = Path()
      ..addRRect(
        RRect.fromLTRBR(
          left + 1.6,
          top + 1.1,
          right - 1.6,
          top + (bottom - top) * 0.42,
          const Radius.circular(4),
        ),
      );
    canvas.drawPath(shine, highlight);

    final cy = top + (bottom - top) * 0.52;
    const xs = [0.30, 0.50, 0.70];
    for (var i = 0; i < 3; i++) {
      final phase = (t + i * 0.18) % 1.0;
      final bounce = math.sin(phase * math.pi);
      final radius = 1.15 + bounce * 0.45;
      final paint = Paint()
        ..color = Color.lerp(
          const Color(0xCC1565C0),
          Colors.white,
          0.35 + bounce * 0.45,
        )!;
      canvas.drawCircle(
        Offset(size.width * xs[i], cy - bounce * 1.5),
        radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CuteTypingPainter oldDelegate) =>
      oldDelegate.t != t;
}

class TypingDot extends StatefulWidget {
  const TypingDot({super.key, this.size = 10});

  final double size;

  @override
  State<TypingDot> createState() => _TypingDotState();
}

class _TypingDotState extends State<TypingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.28, end: 1).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.82, end: 1).animate(
          CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
        ),
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: const Color(0xFF90CAF9),
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF0B0B0B), width: 1.6),
            boxShadow: const [
              BoxShadow(color: Color(0x6690CAF9), blurRadius: 5),
            ],
          ),
        ),
      ),
    );
  }
}

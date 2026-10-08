import 'package:flutter/material.dart';

class ForceLockButton extends StatefulWidget {
  const ForceLockButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<ForceLockButton> createState() => _ForceLockButtonState();
}

class _ForceLockButtonState extends State<ForceLockButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Karşı tarafı hesap makinesine gönder',
      onPressed: widget.onPressed,
      icon: SizedBox(
        width: 28,
        height: 28,
        child: Stack(
          alignment: Alignment.center,
          children: [
            RotationTransition(
              turns: _controller,
              child: const Icon(
                Icons.sync,
                size: 28,
                color: Color(0xFF90CAF9),
              ),
            ),
            const Icon(
              Icons.calculate_outlined,
              size: 16,
              color: Colors.white70,
            ),
          ],
        ),
      ),
    );
  }
}

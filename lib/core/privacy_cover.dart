import 'dart:ui';

import 'package:flutter/material.dart';

import 'theme/calculator_theme.dart';

/// Recents / uygulama değişiminde sohbeti hesap makinesi görünümüyle örter.
class PrivacyCover extends StatefulWidget {
  const PrivacyCover({super.key, required this.child});

  final Widget child;

  @override
  State<PrivacyCover> createState() => _PrivacyCoverState();
}

class _PrivacyCoverState extends State<PrivacyCover>
    with WidgetsBindingObserver {
  bool _covered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final shouldCover = state != AppLifecycleState.resumed;
    if (shouldCover != _covered) {
      setState(() => _covered = shouldCover);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_covered)
          Positioned.fill(
            child: AbsorbPointer(
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: ColoredBox(
                    color: CalculatorTheme.background.withValues(alpha: 0.92),
                    child: const SafeArea(
                      child: Align(
                        alignment: Alignment.bottomRight,
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(24, 16, 24, 32),
                          child: Text(
                            '0',
                            style: TextStyle(
                              color: CalculatorTheme.displayText,
                              fontSize: 72,
                              fontWeight: FontWeight.w200,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

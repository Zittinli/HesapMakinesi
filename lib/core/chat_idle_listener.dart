import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/settings_service.dart';
import 'idle_warning_look.dart';

class ChatIdleScope extends InheritedWidget {
  const ChatIdleScope({
    super.key,
    required this.reset,
    required super.child,
  });

  final VoidCallback reset;

  static ChatIdleScope? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ChatIdleScope>();
  }

  @override
  bool updateShouldNotify(ChatIdleScope oldWidget) => reset != oldWidget.reset;
}

class ChatIdleListener extends StatefulWidget {
  const ChatIdleListener({
    super.key,
    required this.onIdle,
    required this.child,
  });

  final VoidCallback onIdle;
  final Widget child;

  @override
  State<ChatIdleListener> createState() => _ChatIdleListenerState();
}

class _ChatIdleListenerState extends State<ChatIdleListener> {
  Timer? _timer;
  DateTime? _deadline;
  bool _pausedForOverlay = false;
  bool _fastTicks = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bump());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _bump() {
    final seconds = context.read<SettingsService>().chatIdleSeconds;
    _deadline = DateTime.now().add(Duration(seconds: seconds));
    _pausedForOverlay = false;
    _fastTicks = false;
    _armTimer();
    if (mounted) setState(() {});
  }

  void _onTick() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      _pausedForOverlay = true;
      return;
    }
    if (_pausedForOverlay) {
      _deadline = DateTime.now().add(
        Duration(seconds: context.read<SettingsService>().chatIdleSeconds),
      );
      _pausedForOverlay = false;
      _fastTicks = false;
      _armTimer();
      return;
    }
    final deadline = _deadline;
    if (deadline == null) return;
    if (DateTime.now().isAfter(deadline)) {
      _timer?.cancel();
      widget.onIdle();
      return;
    }
    final warning = IdleWarningLook.progress(deadline) > 0;
    if (warning) {
      if (!_fastTicks) {
        _fastTicks = true;
        _armTimer(fast: true);
      }
      setState(() {});
    }
  }

  void _armTimer({bool fast = false}) {
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(milliseconds: fast ? 80 : 1000),
      (_) => _onTick(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = IdleWarningLook.progress(_deadline);
    return ChatIdleScope(
      reset: _bump,
      child: Stack(
        children: [
          widget.child,
          if (progress > 0)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.center,
                      radius: 1.2,
                      colors: [
                        IdleWarningLook.overlayInner(progress),
                        IdleWarningLook.overlayEdge(progress),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

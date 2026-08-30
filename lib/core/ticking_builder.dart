import 'dart:async';

import 'package:flutter/material.dart';

/// Sadece bu alt ağacı yeniler; üst StreamBuilder'ları bozmaz.
class TickingBuilder extends StatefulWidget {
  const TickingBuilder({
    super.key,
    this.interval = const Duration(seconds: 1),
    required this.builder,
  });

  final Duration interval;
  final WidgetBuilder builder;

  @override
  State<TickingBuilder> createState() => _TickingBuilderState();
}

class _TickingBuilderState extends State<TickingBuilder> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.interval, (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

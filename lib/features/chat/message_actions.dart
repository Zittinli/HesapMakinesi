import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/emoji_catalog.dart';

class MessageMenuEntry {
  const MessageMenuEntry(this.value, this.label, {this.color});

  final String value;
  final String label;
  final Color? color;
}

Future<String?> showMessageActions({
  required BuildContext context,
  required BuildContext anchorContext,
  required bool isMine,
  required List<String> quickEmojis,
  required List<MessageMenuEntry> entries,
}) {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (overlay == null || !overlay.attached) return Future.value();
  final anchor = anchorContext.findRenderObject();
  var top = overlay.size.height * 0.35;
  var bottom = top + 48;
  if (anchor is RenderBox && anchor.attached && anchor.hasSize) {
    final origin = anchor.localToGlobal(Offset.zero, ancestor: overlay);
    top = origin.dy;
    bottom = origin.dy + anchor.size.height;
  }

  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Kapat',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return _MessageActionOverlay(
        anchorTop: top,
        anchorBottom: bottom,
        screenSize: overlay.size,
        isMine: isMine,
        quickEmojis: quickEmojis,
        entries: entries,
      );
    },
  );
}

class _MessageActionOverlay extends StatelessWidget {
  const _MessageActionOverlay({
    required this.anchorTop,
    required this.anchorBottom,
    required this.screenSize,
    required this.isMine,
    required this.quickEmojis,
    required this.entries,
  });

  final double anchorTop;
  final double anchorBottom;
  final Size screenSize;
  final bool isMine;
  final List<String> quickEmojis;
  final List<MessageMenuEntry> entries;

  static const _emojiHeight = 44.0;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final minTop = pad.top + 4;
    final menuHeight = entries.length * 36.0 + 12;
    final emojiTop = (anchorTop - _emojiHeight - 6)
        .clamp(minTop, math.max(minTop, screenSize.height - _emojiHeight - 8))
        .toDouble();
    final belowTop = anchorBottom + 6;
    final spaceBelow = screenSize.height - pad.bottom - 8 - belowTop;
    final fitsBelow = spaceBelow >= menuHeight;
    final double menuTop;
    final double menuMaxHeight;
    if (fitsBelow) {
      menuTop = belowTop;
      menuMaxHeight = spaceBelow;
    } else {
      final roomAbove = math.max(0.0, emojiTop - minTop - 6);
      if (roomAbove >= 36) {
        final height = math.min(menuHeight, roomAbove);
        menuTop = emojiTop - 6 - height;
        menuMaxHeight = height;
      } else {
        menuTop = math.max(minTop, belowTop);
        menuMaxHeight = math.max(36.0, spaceBelow);
      }
    }

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.pop(context),
            ),
          ),
          Positioned(
            top: emojiTop,
            left: isMine ? null : 10,
            right: isMine ? 10 : null,
            child: _EmojiTray(emojis: quickEmojis),
          ),
          Positioned(
            top: menuTop,
            left: isMine ? null : 10,
            right: isMine ? 10 : null,
            child: menuMaxHeight < menuHeight
                ? ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: menuMaxHeight),
                    child: _OptionMenu(entries: entries),
                  )
                : _OptionMenu(entries: entries),
          ),
        ],
      ),
    );
  }
}

class _EmojiTray extends StatelessWidget {
  const _EmojiTray({required this.emojis});

  final List<String> emojis;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF161616),
      elevation: 6,
      shadowColor: Colors.black,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final emoji in emojis)
                _TrayButton(
                  onTap: () => Navigator.pop(context, 'react:$emoji'),
                  child: Text(emoji, style: const TextStyle(fontSize: 20)),
                ),
              _TrayButton(
                tooltip: 'Hızlı emojileri düzenle',
                onTap: () => Navigator.pop(context, 'edit-quick'),
                child: const Icon(
                  Icons.edit_outlined,
                  color: Colors.white54,
                  size: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrayButton extends StatelessWidget {
  const _TrayButton({
    required this.onTap,
    required this.child,
    this.tooltip,
  });

  final VoidCallback onTap;
  final Widget child;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(width: 40, height: 40, child: Center(child: child)),
    );
    final tip = tooltip;
    if (tip == null) return button;
    return Tooltip(message: tip, child: button);
  }
}

class _OptionMenu extends StatelessWidget {
  const _OptionMenu({required this.entries});

  final List<MessageMenuEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF161616),
      elevation: 6,
      shadowColor: Colors.black,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
        child: IntrinsicWidth(
        child: Listener(
          behavior: HitTestBehavior.opaque,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final entry in entries)
                  InkWell(
                    onTap: () => Navigator.pop(context, entry.value),
                    child: SizedBox(
                      height: 36,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            entry.label,
                            style: TextStyle(
                              color: entry.color ?? Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showQuickEmojiEditor({
  required BuildContext context,
  required List<String> selected,
  required Future<void> Function(List<String> emojis) onSave,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF141414),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (context, controller) {
          return _QuickEmojiEditor(
            initial: selected,
            scrollController: controller,
            onSave: onSave,
          );
        },
      );
    },
  );
}

class _QuickEmojiEditor extends StatefulWidget {
  const _QuickEmojiEditor({
    required this.initial,
    required this.scrollController,
    required this.onSave,
  });

  final List<String> initial;
  final ScrollController scrollController;
  final Future<void> Function(List<String> emojis) onSave;

  @override
  State<_QuickEmojiEditor> createState() => _QuickEmojiEditorState();
}

class _QuickEmojiEditorState extends State<_QuickEmojiEditor> {
  late List<String> _selected;
  Timer? _timer;
  Future<void> _queue = Future<void>.value();

  @override
  void initState() {
    super.initState();
    _selected = EmojiCatalog.normalize(widget.initial);
  }

  @override
  void dispose() {
    _timer?.cancel();
    final pending = List<String>.from(_selected);
    unawaited(_enqueue(pending));
    super.dispose();
  }

  void _toggle(String emoji) {
    final next = [..._selected];
    if (next.contains(emoji)) {
      if (next.length == 1) return;
      next.remove(emoji);
    } else if (next.length >= EmojiCatalog.maxQuick) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('En fazla 8 hızlı emoji seçebilirsin.')),
      );
      return;
    } else {
      next.add(emoji);
    }
    setState(() => _selected = next);
    _timer?.cancel();
    final snapshot = List<String>.from(next);
    _timer = Timer(const Duration(milliseconds: 280), () {
      unawaited(_enqueue(snapshot));
    });
  }

  Future<void> _enqueue(List<String> emojis) {
    final completer = Completer<void>();
    _queue = _queue.then((_) async {
      try {
        await widget.onSave(emojis);
      } catch (error) {
        if (mounted) {
          final text = error.toString().replaceFirst('Bad state: ', '');
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(text)));
        }
      } finally {
        if (!completer.isCompleted) completer.complete();
      }
    });
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white24,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 14, 20, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Hızlı emojiler',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Tepside görünenler. ${_selected.length}/${EmojiCatalog.maxQuick} seçili, hesabına kaydedilir.',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
        ),
        Expanded(
          child: ListView(
            controller: widget.scrollController,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              for (final group in EmojiCatalog.groups) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                  child: Text(
                    group.$1,
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final emoji in group.$2)
                      _EmojiChoice(
                        emoji: emoji,
                        selected: _selected.contains(emoji),
                        onTap: () => _toggle(emoji),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _EmojiChoice extends StatelessWidget {
  const _EmojiChoice({
    required this.emoji,
    required this.selected,
    required this.onTap,
  });

  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF2C2C2C) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? const Color(0xFF90CAF9) : const Color(0xFF2A2A2A),
          ),
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 22)),
      ),
    );
  }
}

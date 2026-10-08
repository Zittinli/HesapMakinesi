import 'package:flutter/material.dart';

import '../../core/staff_perms.dart';

class StaffPermToggles extends StatelessWidget {
  const StaffPermToggles({
    super.key,
    required this.perms,
    required this.onToggle,
    this.enabled = true,
  });

  final Iterable<String> perms;
  final ValueChanged<String> onToggle;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final current = StaffPerm.normalize(perms);
    return Column(
      children: [
        for (final perm in StaffPerm.all)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(
              StaffPerm.labelOf(perm),
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            trailing: IconButton(
              tooltip: current.contains(perm) ? 'Yetkiyi al' : 'Yetki ver',
              onPressed: enabled ? () => onToggle(perm) : null,
              icon: Icon(
                current.contains(perm) ? Icons.check : Icons.close,
                color: current.contains(perm)
                    ? const Color(0xFFA5D6A7)
                    : const Color(0xFFFF8A80),
              ),
            ),
          ),
      ],
    );
  }
}

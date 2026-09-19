import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/notification_look.dart';
import '../../services/notification_service.dart';
import '../../services/settings_service.dart';

class NotificationSettingsScreen extends StatelessWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final preview = NotificationCopy.of(
      look: settings.notificationLook,
      sender: 'Ahmet',
      preview: 'Yarın görüşürüz',
    );
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B0B),
        foregroundColor: Colors.white70,
        elevation: 0,
        title: const Text(
          'Bildirim görünümü',
          style: TextStyle(fontWeight: FontWeight.w400),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          const Text(
            'Bildirimde böyle görünür.',
            style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 14),
          _NotificationPreview(copy: preview),
          const SizedBox(height: 12),
          ...NotificationLook.values.map((look) {
            return RadioListTile<NotificationLook>(
              value: look,
              groupValue: settings.notificationLook,
              onChanged: (value) {
                if (value != null) settings.setNotificationLook(value);
              },
              activeColor: Colors.white70,
              contentPadding: EdgeInsets.zero,
              title: Text(
                look.label,
                style: const TextStyle(color: Colors.white70, fontSize: 15),
              ),
              subtitle: Text(
                look.hint,
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            );
          }),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: settings.soundEnabled,
            onChanged: settings.notificationLook == NotificationLook.off
                ? null
                : settings.setSoundEnabled,
            title: const Text('Ses', style: TextStyle(color: Colors.white70)),
            activeColor: Colors.white70,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: settings.vibrateEnabled,
            onChanged: settings.notificationLook == NotificationLook.off
                ? null
                : settings.setVibrateEnabled,
            title: const Text(
              'Titreşim',
              style: TextStyle(color: Colors.white70),
            ),
            activeColor: Colors.white70,
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: const BorderSide(color: Colors.white24),
            ),
            onPressed: settings.notificationLook == NotificationLook.off
                ? null
                : () => context.read<NotificationService>().showPreview(),
            child: const Text('Örnek bildirimi göster'),
          ),
        ],
      ),
    );
  }
}

class _NotificationPreview extends StatelessWidget {
  const _NotificationPreview({required this.copy});

  final NotificationCopy? copy;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF161616),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: copy == null
          ? const Text(
              'Bildirim yok.',
              style: TextStyle(color: Colors.white38, fontSize: 13),
            )
          : Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.calculate_outlined,
                    color: Colors.white70,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        copy!.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        copy!.body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

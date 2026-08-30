import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../services/chat_service.dart';
import '../chat/chat_screen.dart';

class UserSearchScreen extends StatefulWidget {
  const UserSearchScreen({super.key});

  @override
  State<UserSearchScreen> createState() => _UserSearchScreenState();
}

class _UserSearchScreenState extends State<UserSearchScreen> {
  final _emailController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _startChat() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final authService = context.read<AuthService>();
      final chatService = context.read<ChatService>();
      final currentUserId = authService.currentUser!.uid;

      final user = await authService.findUserByEmail(email);
      if (user == null) {
        setState(() => _error = 'Bu e-posta ile kullanici bulunamadi.');
        return;
      }

      if (user.id == currentUserId) {
        setState(() => _error = 'Kendinizle sohbet baslatamazsiniz.');
        return;
      }

      final chatId = await chatService.getOrCreateChat(currentUserId, user.id);
      await chatService.promotePendingToChat(
        senderId: currentUserId,
        recipientEmail: user.email,
        chatId: chatId,
      );
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            chatId: chatId,
            otherUserId: user.id,
            otherUserName: user.displayName.isNotEmpty
                ? user.displayName
                : user.email,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kullanici Ara')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'E-posta adresi',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _startChat(),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            FilledButton(
              onPressed: _isLoading ? null : _startChat,
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Sohbet Baslat'),
            ),
          ],
        ),
      ),
    );
  }
}

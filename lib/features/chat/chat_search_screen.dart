import 'package:flutter/material.dart';

import '../../core/chat_format.dart';
import '../../models/message_model.dart';

class ChatSearchScreen extends StatefulWidget {
  const ChatSearchScreen({
    super.key,
    required this.messages,
    required this.myId,
  });

  final List<ChatMessage> messages;
  final String myId;

  @override
  State<ChatSearchScreen> createState() => _ChatSearchScreenState();
}

class _ChatSearchScreenState extends State<ChatSearchScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim().toLowerCase();
    final hits = query.isEmpty
        ? const <ChatMessage>[]
        : widget.messages
            .where((item) => item.preview.toLowerCase().contains(query))
            .toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B0B),
        foregroundColor: Colors.white70,
        title: TextField(
          controller: _controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Bu sohbette ara',
            hintStyle: TextStyle(color: Colors.white30),
            border: InputBorder.none,
          ),
          onChanged: (_) => setState(() {}),
        ),
      ),
      body: hits.isEmpty
          ? Center(
              child: Text(
                query.isEmpty ? 'Kelime yazin.' : 'Sonuc yok.',
                style: const TextStyle(color: Colors.white38),
              ),
            )
          : ListView.separated(
              itemCount: hits.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: Color(0xFF1C1C1C)),
              itemBuilder: (context, index) {
                final message = hits[index];
                return ListTile(
                  title: Text(
                    message.preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  subtitle: Text(
                    ChatFormat.eventDateTime(message.createdAt),
                    style: const TextStyle(color: Colors.white30, fontSize: 12),
                  ),
                );
              },
            ),
    );
  }
}

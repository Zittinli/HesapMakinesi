import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/chat_format.dart';
import '../../models/message_model.dart';
import '../../services/chat_service.dart';

class ChatSearchScreen extends StatefulWidget {
  const ChatSearchScreen({
    super.key,
    required this.messages,
    required this.myId,
    required this.chatId,
  });

  final List<ChatMessage> messages;
  final String myId;
  final String chatId;

  @override
  State<ChatSearchScreen> createState() => _ChatSearchScreenState();
}

class _ChatSearchScreenState extends State<ChatSearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<ChatMessage> _remoteHits = const [];
  bool _loading = false;
  int _searchGeneration = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (widget.chatId.isEmpty || query.isEmpty) {
      setState(() {
        _loading = false;
        _remoteHits = const [];
      });
      return;
    }
    final generation = ++_searchGeneration;
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final hits = await context.read<ChatService>().searchMessagesInChat(
          chatId: widget.chatId,
          query: query,
        );
        if (!mounted || generation != _searchGeneration) return;
        setState(() {
          _remoteHits = hits;
          _loading = false;
        });
      } catch (_) {
        if (!mounted || generation != _searchGeneration) return;
        setState(() {
          _remoteHits = const [];
          _loading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim().toLowerCase();
    final hits = query.isEmpty
        ? const <ChatMessage>[]
        : widget.chatId.isNotEmpty
        ? _remoteHits
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
          onChanged: _onQueryChanged,
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white24),
            )
          : hits.isEmpty
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
                  onTap: () => Navigator.pop(context, message.id),
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

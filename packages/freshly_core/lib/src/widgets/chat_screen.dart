import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../network/api_client.dart';
import '../realtime/realtime_client.dart';
import '../theme/freshly_theme.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    required this.bookingId,
    required this.currentUserId,
    required this.api,
    required this.realtime,
    this.title = 'Chat',
    super.key,
  });

  final String bookingId;
  final String currentUserId;
  final FreshlyApi api;
  final RealtimeClient realtime;
  final String title;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <ChatMessage>[];
  StreamSubscription? _sub;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _sub = widget.realtime.messages.listen((msg) {
      if (msg.bookingId == widget.bookingId) {
        setState(() {
          _messages.add(msg);
        });
        _scrollToBottom();
      }
    });
    widget.realtime.joinBooking(widget.bookingId);
  }

  Future<void> _loadHistory() async {
    try {
      final history = await widget.api.getChatHistory(widget.bookingId);
      if (mounted) {
        setState(() {
          _messages.addAll(history);
          _loading = false;
        });
        _scrollToBottom();
        await widget.api.markChatAsRead(widget.bookingId);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();

    try {
      await widget.api.sendChatMessage(widget.bookingId, text);
      // Realtime listener will add it to the list
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not send message')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.chat_bubble_outline,
                                size: 48, color: FreshlyColors.inkMuted),
                            const SizedBox(height: 12),
                            Text('No messages yet',
                                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: FreshlyColors.inkMuted)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(FreshlySpacing.md),
                        itemCount: _messages.length,
                        itemBuilder: (context, i) {
                          final msg = _messages[i];
                          final isMe = msg.authorId == widget.currentUserId;
                          return _ChatBubble(message: msg, isMe: isMe);
                        },
                      ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: const Border(top: BorderSide(color: FreshlyColors.line)),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: FreshlyColors.line.withValues(alpha: 0.3),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.send, color: FreshlyColors.mint),
                    onPressed: _send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    widget.realtime.leaveBooking(widget.bookingId);
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message, required this.isMe});
  final ChatMessage message;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isMe ? FreshlyColors.mint : FreshlyColors.line.withValues(alpha: 0.4),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              message.body,
              style: TextStyle(color: isMe ? Colors.white : Colors.black, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              DateFormat('HH:mm').format(message.createdAt),
              style: TextStyle(
                color: isMe ? Colors.white70 : FreshlyColors.inkMuted,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

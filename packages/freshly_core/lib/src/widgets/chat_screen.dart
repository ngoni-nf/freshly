import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';
import '../theme/freshly_icons.dart';
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
  StreamSubscription? _readSub;
  bool _loading = true;
  bool _expired = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _sub = widget.realtime.messages.listen((msg) {
      if (msg.bookingId != widget.bookingId || !mounted) return;
      // The socket delivers to everyone in the room, the sender included, and
      // a reconnect can replay what history already loaded. Keyed on id so
      // neither shows the same message twice.
      if (_messages.any((m) => m.id == msg.id)) return;
      setState(() => _messages.add(msg));
      _scrollToBottom();
    });
    _readSub = widget.realtime.chatRead.listen((bookingId) {
      if (bookingId != widget.bookingId || !mounted) return;
      // Everything of mine is now read; there is no per-message state to
      // reconcile, which is why the event carries only the booking.
      setState(() {
        for (var i = 0; i < _messages.length; i++) {
          final m = _messages[i];
          if (m.authorId == widget.currentUserId && !m.isRead) {
            _messages[i] = ChatMessage(
              id: m.id,
              bookingId: m.bookingId,
              authorId: m.authorId,
              body: m.body,
              createdAt: m.createdAt,
              isRead: true,
            );
          }
        }
      });
    });
    widget.realtime.joinBooking(widget.bookingId);
  }

  Future<void> _loadHistory() async {
    // The messages first, and on their own.
    //
    // These used to share a try block with the booking fetch below, so
    // anything that went wrong there — a parse, a 403, a timeout — threw away
    // a conversation that had already loaded. The catch then swallowed it
    // silently and the screen said "No messages yet", which is
    // indistinguishable from an empty conversation and sends somebody looking
    // for a message that is sitting on the server.
    try {
      final history = await widget.api.getChatHistory(widget.bookingId);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(history);
        _loading = false;
      });
      _scrollToBottom();
      unawaited(widget.api.markChatAsRead(widget.bookingId).catchError((_) {}));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
      return;
    }

    // Whether the conversation has closed is a separate question, and one the
    // screen can survive not knowing: failing to answer it leaves the composer
    // open and the server refuses the send, which is the safe direction.
    try {
      final booking = await widget.api.booking(widget.bookingId);
      if (!mounted || !booking.status.isTerminal) return;
      final closedAt =
          booking.completedAt ?? booking.cancelledAt ?? booking.createdAt;
      if (DateTime.now().difference(closedAt).inHours >= 24) {
        setState(() => _expired = true);
      }
    } catch (_) {
      // Deliberately ignored — see above.
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
          if (_expired)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: FreshlyColors.line.withValues(alpha: 0.5),
              child: Row(
                children: [
                  const Icon(FreshlyIcons.lock,
                      size: 16, color: FreshlyColors.inkMuted),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'This conversation is closed. You can no longer send messages.',
                      style: TextStyle(
                          fontSize: 13,
                          color: FreshlyColors.inkMuted,
                          height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(FreshlySpacing.lg),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: FreshlyColors.inkMuted)),
                          const SizedBox(height: FreshlySpacing.md),
                          OutlinedButton(
                            onPressed: () {
                              setState(() {
                                _error = null;
                                _loading = true;
                              });
                              _loadHistory();
                            },
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(FreshlyIcons.chat,
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
          if (!_expired)
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
                      icon: const Icon(FreshlyIcons.send, color: FreshlyColors.mint),
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
    _readSub?.cancel();
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
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DateFormat('HH:mm').format(message.createdAt),
                  style: TextStyle(
                    color: isMe ? Colors.white70 : FreshlyColors.inkMuted,
                    fontSize: 10,
                  ),
                ),
                // Only on your own messages. A receipt on someone else's is
                // meaningless — you obviously read it, you are looking at it.
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    message.isRead
                        ? FreshlyIcons.checkDouble
                        : FreshlyIcons.check,
                    size: 12,
                    // Read is the state worth noticing, so it is the one that
                    // gets colour; delivered stays quiet.
                    color: message.isRead
                        ? FreshlyColors.mintSoft
                        : Colors.white54,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

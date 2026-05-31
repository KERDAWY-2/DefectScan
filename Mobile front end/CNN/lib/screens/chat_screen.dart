import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_app_bar.dart';

class ChatScreen extends StatefulWidget {
  final int chatUserId; // For normal users, this is their own ID. For admins, this is the user they clicked on.

  const ChatScreen({super.key, required this.chatUserId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _msgController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  final ScrollController _scrollController = ScrollController();
  WebSocketChannel? _channel;
  bool _loading = true;
  bool _aiMode = false;     // Human (false) vs AI assistant (true)
  bool _aiThinking = false; // waiting on a Gemini reply
  int? _myId;

  @override
  void initState() {
    super.initState();
    _myId = Provider.of<AuthProvider>(context, listen: false).user?['id'];
    _initChat();
  }

  Future<void> _initChat() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final token = auth.token!;

    // 1. Fetch History
    try {
      final history = await ApiService.getChatHistory(widget.chatUserId, token);
      if (!mounted) return;
      setState(() {
        _messages.addAll(history.map((e) => e as Map<String, dynamic>));
        _loading = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error loading history: $e")));
    }

    // 2. Connect to WebSocket (host derived from the central baseUrl).
    _channel = WebSocketChannel.connect(
      Uri.parse("$wsBaseUrl/chat/ws/${widget.chatUserId}?token=$token"),
    );

    // 3. Listen for incoming messages
    _channel!.stream.listen((messageData) {
      final parsedMessage = jsonDecode(messageData) as Map<String, dynamic>;
      setState(() {
        _messages.add(parsedMessage);
      });
      _scrollToBottom();
    });
  }

  void _scrollToBottom() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;

    if (_aiMode) {
      // AI mode goes over REST; nothing is broadcast, so append optimistically.
      _msgController.clear();
      setState(() {
        _messages.add({"sender_id": _myId, "content": text, "is_ai": false});
        _aiThinking = true;
      });
      _scrollToBottom();
      try {
        final auth = Provider.of<AuthProvider>(context, listen: false);
        final reply = await ApiService.askAi(widget.chatUserId, text, auth.token!);
        if (mounted) setState(() => _messages.add({"sender_id": null, "content": reply, "is_ai": true}));
      } catch (e) {
        if (mounted) setState(() => _messages.add({"sender_id": null, "content": "AI error: $e", "is_ai": true}));
      } finally {
        if (mounted) setState(() => _aiThinking = false);
        _scrollToBottom();
      }
    } else {
      // Human mode: send over the WebSocket; the broadcast echo adds it to the list.
      if (_channel == null) return;
      _channel!.sink.add(text);
      _msgController.clear();
    }
  }

  @override
  void dispose() {
    _channel?.sink.close();
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: "Support Chat"),
      body: Column(
        children: [
          // Human / AI mode switch
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text("Human"), icon: Icon(Icons.support_agent)),
                ButtonSegment(value: true, label: Text("AI Assistant"), icon: Icon(Icons.smart_toy)),
              ],
              selected: {_aiMode},
              onSelectionChanged: (s) => setState(() => _aiMode = s.first),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? _emptyState()
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          final isAi = msg['is_ai'] == true;
                          final isMe = !isAi && msg['sender_id'] == _myId;

                          // Bubble colors: me → brand blue (white text);
                          // AI → amber-tinted; other human → soft neutral.
                          final Color bubbleColor = isMe
                              ? kBrandBlue
                              : isAi
                                  ? kBrandAmber.withValues(alpha: 0.16)
                                  : const Color(0xFFEDF1F7);
                          final Color textColor = isMe ? Colors.white : kInk;

                          return Align(
                            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: MediaQuery.of(context).size.width * 0.78,
                              ),
                              child: Column(
                                crossAxisAlignment:
                                    isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                children: [
                                  if (isAi)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 4, bottom: 3),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: const [
                                          Icon(Icons.smart_toy, size: 14, color: kBrandAmberDark),
                                          SizedBox(width: 4),
                                          Text(
                                            "AI Assistant",
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: kBrandAmberDark,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: bubbleColor,
                                      border: isAi
                                          ? Border.all(color: kBrandAmber.withValues(alpha: 0.4))
                                          : null,
                                      borderRadius: BorderRadius.circular(18).copyWith(
                                        bottomRight: isMe ? const Radius.circular(2) : const Radius.circular(18),
                                        bottomLeft: !isMe ? const Radius.circular(2) : const Radius.circular(18),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: (isMe ? kBrandBlue : kBrandBlue.withValues(alpha: 0.5))
                                              .withValues(alpha: 0.12),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Text(
                                      msg['content'] ?? '',
                                      style: TextStyle(
                                        color: textColor,
                                        fontSize: 15.5,
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),

          if (_aiThinking)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: kBrandAmber.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: kBrandAmber.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(kBrandAmberDark),
                          ),
                        ),
                        SizedBox(width: 8),
                        Text(
                          "AI is typing...",
                          style: TextStyle(color: kBrandAmberDark, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // Input Field
          Container(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
            decoration: BoxDecoration(
              color: kCardSurface,
              boxShadow: [
                BoxShadow(
                  color: kBrandBlue.withValues(alpha: 0.10),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: kSurface,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: kBrandBlue.withValues(alpha: 0.12)),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: _msgController,
                        minLines: 1,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: _aiMode ? "Ask the AI assistant..." : "Type a message...",
                          border: InputBorder.none,
                          filled: false,
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: _aiMode ? kBrandAmber : kBrandBlue,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _sendMessage,
                      child: Padding(
                        padding: const EdgeInsets.all(11),
                        child: Icon(
                          Icons.send,
                          size: 22,
                          color: _aiMode ? const Color(0xFF3A2A05) : Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: (_aiMode ? kBrandAmber : kBrandBlue).withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _aiMode ? Icons.smart_toy_outlined : Icons.support_agent,
                size: 52,
                color: _aiMode ? kBrandAmberDark : kBrandBlue,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _aiMode ? "Ask the AI assistant" : "Start the conversation",
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kInk),
            ),
            const SizedBox(height: 6),
            Text(
              _aiMode
                  ? "Get instant answers about defects and reports."
                  : "Send a message to reach our support team.",
              style: const TextStyle(color: kInkMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

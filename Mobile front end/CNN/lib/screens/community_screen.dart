import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_app_bar.dart';

const List<String> kEmojis = ["👍", "❤️", "😮", "😢", "🔧"];

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  final List<Map<String, dynamic>> _posts = [];
  final TextEditingController _composeController = TextEditingController();
  final Set<String> _myReactions = {}; // keys like "post:5:👍" / "comment:3:❤️"
  final ImagePicker _picker = ImagePicker();
  WebSocketChannel? _channel;
  bool _loading = true;
  String? _pendingImagePath; // uploaded image path waiting to be attached to a post

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    try {
      final posts = await ApiService.getCommunityPosts(token);
      if (!mounted) return;
      setState(() {
        for (final p in posts) {
          final post = p as Map<String, dynamic>;
          _seedMyReactions(post['reactions'], "post", post['id']);
          for (final c in (post['comments'] as List? ?? [])) {
            _seedMyReactions(c['reactions'], "comment", c['id']);
          }
          _posts.add(post);
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error loading feed: $e")));
    }

    _channel = WebSocketChannel.connect(Uri.parse("$wsBaseUrl/community/ws?token=$token"));
    _channel!.stream.listen(_onEvent);
  }

  void _seedMyReactions(dynamic reactions, String type, dynamic id) {
    for (final r in (reactions as List? ?? [])) {
      if (r['reacted'] == true) _myReactions.add("$type:$id:${r['emoji']}");
    }
  }

  void _onEvent(dynamic raw) {
    if (!mounted) return;
    final event = jsonDecode(raw) as Map<String, dynamic>;
    setState(() {
      switch (event['type']) {
        case 'new_post':
          _posts.insert(0, event['post'] as Map<String, dynamic>);
          break;
        case 'new_comment':
          final comment = event['comment'] as Map<String, dynamic>;
          final post = _findPost(comment['post_id']);
          if (post != null) {
            (post['comments'] as List).add(comment);
          }
          break;
        case 'reaction':
          _applyReaction(event);
          break;
      }
    });
  }

  Map<String, dynamic>? _findPost(dynamic postId) {
    for (final p in _posts) {
      if (p['id'] == postId) return p;
    }
    return null;
  }

  void _applyReaction(Map<String, dynamic> event) {
    final emoji = event['emoji'];
    final count = event['count'] as int;
    final postId = event['post_id'];
    final commentId = event['comment_id'];

    List? targetReactions;
    if (commentId != null) {
      for (final p in _posts) {
        for (final c in (p['comments'] as List? ?? [])) {
          if (c['id'] == commentId) {
            targetReactions = c['reactions'] as List?;
            c['reactions'] = targetReactions ??= [];
          }
        }
      }
    } else {
      final post = _findPost(postId);
      if (post != null) {
        targetReactions = post['reactions'] as List?;
        post['reactions'] = targetReactions ??= [];
      }
    }
    if (targetReactions == null) return;

    targetReactions.removeWhere((r) => r['emoji'] == emoji);
    if (count > 0) {
      targetReactions.add({"emoji": emoji, "count": count});
    }
  }

  void _send(Map<String, dynamic> action) {
    _channel?.sink.add(jsonEncode(action));
  }

  Future<void> _attachImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 85);
    if (image == null) return;
    if (!mounted) return;
    final token = Provider.of<AuthProvider>(context, listen: false).token!;
    try {
      final path = await ApiService.uploadCommunityImage(image, token);
      setState(() => _pendingImagePath = path);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Image upload failed: $e")));
    }
  }

  void _submitPost() {
    final content = _composeController.text.trim();
    if (content.isEmpty && _pendingImagePath == null) return;
    _send({"action": "post", "content": content, "image_path": _pendingImagePath});
    _composeController.clear();
    setState(() => _pendingImagePath = null);
  }

  void _toggleReaction(String emoji, {int? postId, int? commentId}) {
    final type = commentId != null ? "comment" : "post";
    final id = commentId ?? postId;
    final key = "$type:$id:$emoji";
    setState(() {
      if (_myReactions.contains(key)) {
        _myReactions.remove(key);
      } else {
        _myReactions.add(key);
      }
    });
    _send({"action": "react", "emoji": emoji, "post_id": postId, "comment_id": commentId});
  }

  @override
  void dispose() {
    _channel?.sink.close();
    _composeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: "Community"),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _posts.isEmpty
                    ? _emptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
                        itemCount: _posts.length,
                        itemBuilder: (context, index) => _PostCard(
                          // Keyed by post id so per-card state (open reply box,
                          // typed text) stays with its post when a new post is
                          // inserted at the top of the list.
                          key: ValueKey(_posts[index]['id']),
                          post: _posts[index],
                          myReactions: _myReactions,
                          onReact: _toggleReaction,
                          onReply: (postId, text) => _send({"action": "comment", "post_id": postId, "content": text}),
                        ),
                      ),
          ),
          _composer(),
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
                color: kBrandBlue.withValues(alpha: 0.07),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.forum_outlined, size: 54, color: kBrandBlue),
            ),
            const SizedBox(height: 20),
            const Text(
              "No posts yet",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kInk),
            ),
            const SizedBox(height: 6),
            const Text(
              "Be the first to share something with the community.",
              style: TextStyle(color: kInkMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _composer() {
    return Container(
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_pendingImagePath != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8, left: 4),
                  child: Chip(
                    avatar: const Icon(Icons.image, size: 18, color: kBrandBlue),
                    label: const Text("Image attached"),
                    onDeleted: () => setState(() => _pendingImagePath = null),
                  ),
                ),
              ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  color: kBrandBlue,
                  tooltip: "Attach image",
                  onPressed: _attachImage,
                ),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: kSurface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: kBrandBlue.withValues(alpha: 0.12)),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: _composeController,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: "Share something with the community...",
                        border: InputBorder.none,
                        filled: false,
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Material(
                  color: kBrandAmber,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _submitPost,
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(Icons.send, color: Color(0xFF3A2A05), size: 22),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PostCard extends StatefulWidget {
  final Map<String, dynamic> post;
  final Set<String> myReactions;
  final void Function(String emoji, {int? postId, int? commentId}) onReact;
  final void Function(int postId, String text) onReply;

  const _PostCard({
    super.key,
    required this.post,
    required this.myReactions,
    required this.onReact,
    required this.onReply,
  });

  @override
  State<_PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<_PostCard> {
  final TextEditingController _replyController = TextEditingController();
  bool _showReply = false;

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  int _countFor(dynamic reactions, String emoji) {
    for (final r in (reactions as List? ?? [])) {
      if (r['emoji'] == emoji) return r['count'] as int;
    }
    return 0;
  }

  Widget _reactionRow(dynamic reactions, {int? postId, int? commentId}) {
    final type = commentId != null ? "comment" : "post";
    final id = commentId ?? postId;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: kEmojis.map((emoji) {
        final count = _countFor(reactions, emoji);
        final reacted = widget.myReactions.contains("$type:$id:$emoji");
        return InkWell(
          onTap: () => widget.onReact(emoji, postId: postId, commentId: commentId),
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: reacted ? kBrandBlue.withValues(alpha: 0.10) : kSurface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: reacted
                    ? kBrandBlue.withValues(alpha: 0.45)
                    : kBrandBlue.withValues(alpha: 0.10),
              ),
            ),
            child: Text(
              count > 0 ? "$emoji $count" : emoji,
              style: TextStyle(
                fontSize: 14,
                fontWeight: reacted ? FontWeight.w700 : FontWeight.w500,
                color: reacted ? kBrandBlue : kInk,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final comments = (post['comments'] as List? ?? []);

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    gradient: kBrandGradient,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _initials(post['author_name']),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    post['author_name'] ?? 'User',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: kInk,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if ((post['content'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                post['content'],
                style: const TextStyle(fontSize: 15, color: kInk, height: 1.35),
              ),
            ],
            if (post['image_path'] != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  uploadsUrl(post['image_path']),
                  fit: BoxFit.cover,
                  width: double.infinity,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      height: 180,
                      color: kSurface,
                      alignment: Alignment.center,
                      child: const CircularProgressIndicator(),
                    );
                  },
                  errorBuilder: (context, error, stack) => Container(
                    height: 160,
                    color: kSurface,
                    alignment: Alignment.center,
                    child: const Icon(Icons.broken_image_outlined,
                        size: 38, color: kInkMuted),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            _reactionRow(post['reactions'], postId: post['id'] as int),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.mode_comment_outlined, size: 18),
                label: Text("Reply (${comments.length})"),
                onPressed: () => setState(() => _showReply = !_showReply),
              ),
            ),

            // Comments
            if (comments.isNotEmpty) ...[
              const SizedBox(height: 2),
              ...comments.map<Widget>((c) => Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(
                      color: kSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border(
                        left: BorderSide(
                          color: kBrandBlue.withValues(alpha: 0.25),
                          width: 3,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c['author_name'] ?? 'User',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: kBrandBlue,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          c['content'] ?? '',
                          style: const TextStyle(color: kInk, fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        _reactionRow(c['reactions'], commentId: c['id'] as int),
                      ],
                    ),
                  )),
            ],

            if (_showReply) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _replyController,
                      decoration: const InputDecoration(
                        hintText: "Write a reply...",
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: kBrandBlue,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () {
                        final text = _replyController.text.trim();
                        if (text.isEmpty) return;
                        widget.onReply(post['id'] as int, text);
                        _replyController.clear();
                        setState(() => _showReply = false);
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(Icons.send, size: 20, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _initials(dynamic name) {
    final s = (name ?? 'User').toString().trim();
    if (s.isEmpty) return 'U';
    final parts = s.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
  }
}

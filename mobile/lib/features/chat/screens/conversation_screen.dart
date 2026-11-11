import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/providers.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/kolo_theme.dart';
import '../../../shared/widgets/common.dart';
import '../../auth/auth_controller.dart';

/// Group chat.
///
/// Messages go over HTTP rather than the socket so validation, rate limiting and
/// authorisation are applied on the server for every single one. The socket is
/// for live delivery only. A member who is not in the group is refused by the
/// same check the REST history endpoint uses.
class ConversationScreen extends ConsumerStatefulWidget {
  const ConversationScreen({super.key, required this.slug});

  final String slug;

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  String? _conversationId;
  List<ChatMessage> _messages = const [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = ref.read(apiClientProvider);
      final conversation = await client.get('/comms/groups/${widget.slug}/chat/');
      final id = '${conversation['id'] ?? ''}';
      final rows = await client.getList('/comms/conversations/$id/messages/', query: {'limit': 60});
      if (!mounted) return;
      setState(() {
        _conversationId = id;
        _messages = rows.map(ChatMessage.fromJson).toList();
      });
      _scrollToEnd();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.userMessage);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final body = _input.text.trim();
    final id = _conversationId;
    if (body.isEmpty || id == null || _sending) return;

    setState(() => _sending = true);
    try {
      final data = await ref.read(apiClientProvider).post(
            '/comms/conversations/$id/messages/',
            body: {'body': body},
          );
      if (!mounted) return;
      _input.clear();
      setState(() {
        _messages = [..._messages, ChatMessage.fromJson(data)];
      });
      _scrollToEnd();
    } on ApiException catch (error) {
      if (!mounted) return;
      // The body is kept in the field so nothing typed is lost.
      showMessage(context, error.userMessage, isError: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.kolo;
    final myId = ref.watch(sessionProvider).valueOrNull?.id ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Group chat')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Padding(
                          padding: const EdgeInsets.all(20),
                          child: ErrorNotice(
                            error: ApiException(code: 'chat', message: _error!),
                            onRetry: _load,
                          ),
                        )
                      : _messages.isEmpty
                          ? const EmptyState(
                              icon: Icons.forum_outlined,
                              title: 'No messages yet',
                              message: 'Say hello. Contributions are announced here too, '
                                  'so nobody has to chase anyone.',
                            )
                          : ListView.builder(
                              controller: _scroll,
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                              itemCount: _messages.length,
                              itemBuilder: (context, index) {
                                final message = _messages[index];
                                return _MessageBubble(
                                  message: message,
                                  isMine: message.senderId == myId,
                                );
                              },
                            ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              decoration: BoxDecoration(
                color: palette.surface,
                border: Border(top: BorderSide(color: palette.divider)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Message the group',
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending || _conversationId == null ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send_rounded, size: 20),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.isMine});

  final ChatMessage message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final palette = context.kolo;
    final time = message.createdAt;
    final stamp = time == null
        ? ''
        : '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isMine)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 3),
              child: Text(
                message.senderName,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isMine ? palette.accent : palette.surface,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isMine ? 16 : 4),
                bottomRight: Radius.circular(isMine ? 4 : 16),
              ),
              border: isMine ? null : Border.all(color: palette.divider),
            ),
            child: Text(
              message.isDeleted ? 'This message was removed' : message.body,
              style: TextStyle(
                fontSize: 15,
                height: 1.35,
                color: isMine ? palette.surface : palette.text,
                fontStyle: message.isDeleted ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
          if (stamp.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3, left: 4, right: 4),
              child: Text(stamp, style: Theme.of(context).textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/providers.dart';
import '../../../core/models/models.dart';
import '../../../design/components.dart';
import '../../../design/navigation.dart';
import '../../../design/tokens.dart';
import '../../../design/typography.dart';
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
      koloToast(context, error.userMessage, isError: true);
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
    final c = context.colors;
    final myId = ref.watch(sessionProvider).value?.id ?? '';

    return Scaffold(
      backgroundColor: c.ground,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  KoloSpace.page, KoloSpace.sm, KoloSpace.page, KoloSpace.sm),
              child: Row(
                children: [
                  KoloBackButton(onTap: () => Navigator.of(context).maybePop()),
                  const SizedBox(width: KoloSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Group chat', style: context.text.titleMedium),
                        Text(
                          widget.slug.replaceAll('-', ' '),
                          style: context.text.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: c.hairline, height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Padding(
                          padding: const EdgeInsets.all(20),
                          child: KoloErrorState(
                            message: _error!,
                            title: 'The conversation did not load',
                            onRetry: _load,
                          ),
                        )
                      : _messages.isEmpty
                          ? const KoloEmptyState(
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
            // The composer rides above the keyboard and keeps its own safe area,
            // so the send button is never under the home indicator.
            Container(
              padding: EdgeInsets.fromLTRB(
                  KoloSpace.md, KoloSpace.sm, KoloSpace.md, KoloSpace.sm),
              decoration: BoxDecoration(
                color: c.surface,
                border: Border(top: BorderSide(color: c.hairline)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      style: TextStyle(
                        fontFamily: KoloType.family,
                        fontSize: 15.5,
                        color: c.text,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Message the group',
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: KoloSpace.lg, vertical: KoloSpace.md + 2),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: KoloSpace.sm),
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: FilledButton(
                      onPressed: _sending || _conversationId == null ? null : _send,
                      style: FilledButton.styleFrom(
                        padding: EdgeInsets.zero,
                        shape: const CircleBorder(),
                      ),
                      child: _sending
                          ? SizedBox(
                              width: 17,
                              height: 17,
                              child: CircularProgressIndicator(
                                strokeWidth: 2, color: c.accentOn),
                            )
                          : Icon(Icons.arrow_upward_rounded, size: 21, color: c.accentOn),
                    ),
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
    final c = context.colors;
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
                style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
            padding: const EdgeInsets.symmetric(
                horizontal: KoloSpace.lg, vertical: KoloSpace.md),
            decoration: BoxDecoration(
              color: isMine ? c.accent : c.surface,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(KoloRadius.lg),
                topRight: const Radius.circular(KoloRadius.lg),
                bottomLeft: Radius.circular(isMine ? KoloRadius.lg : KoloRadius.sm),
                bottomRight: Radius.circular(isMine ? KoloRadius.sm : KoloRadius.lg),
              ),
              border: isMine ? null : Border.all(color: c.hairline),
            ),
            child: Text(
              message.isDeleted ? 'This message was removed' : message.body,
              style: TextStyle(
                fontFamily: KoloType.family,
                fontSize: 15,
                height: 1.4,
                color: isMine ? c.accentOn : c.text,
                fontStyle: message.isDeleted ? FontStyle.italic : FontStyle.normal,
              ),
            ),
          ),
          if (stamp.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3, left: 4, right: 4),
              child: Text(stamp, style: context.text.bodySmall?.copyWith(color: c.textFaint)),
            ),
        ],
      ),
    );
  }
}

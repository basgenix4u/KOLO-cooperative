import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/providers.dart';
import '../../../design/components.dart';
import '../../../design/navigation.dart';
import '../../../design/tokens.dart';
import '../../../design/typography.dart';

class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.kind,
    required this.title,
    required this.groupId,
    required this.unread,
    required this.lastBody,
    required this.lastSender,
    required this.lastAt,
  });

  final String id;
  final String kind;
  final String title;
  final String? groupId;
  final int unread;
  final String lastBody;
  final String lastSender;
  final DateTime? lastAt;

  String get initials {
    final parts = title.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return 'KO';
    if (parts.length == 1) {
      final one = parts.first;
      return one.substring(0, one.length >= 2 ? 2 : 1).toUpperCase();
    }
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  factory ConversationSummary.fromJson(Map<String, dynamic> json) {
    final last = json['last_message'];
    final map = last is Map<String, dynamic> ? last : const <String, dynamic>{};
    return ConversationSummary(
      id: '${json['id'] ?? ''}',
      kind: '${json['kind'] ?? 'group'}',
      title: '${json['title'] ?? 'Conversation'}',
      groupId: json['group_id'] == null ? null : '${json['group_id']}',
      unread: json['unread'] is int ? json['unread'] as int : 0,
      lastBody: '${map['body'] ?? ''}',
      lastSender: '${map['sender_name'] ?? ''}',
      lastAt: DateTime.tryParse('${map['created_at'] ?? ''}'),
    );
  }
}

final conversationsProvider = FutureProvider<List<ConversationSummary>>((ref) async {
  final rows = await ref.watch(apiClientProvider).getList('/comms/conversations/');
  return rows.map(ConversationSummary.fromJson).toList();
});

final unreadMessagesProvider = Provider<int>((ref) {
  return ref.watch(conversationsProvider).maybeWhen(
        data: (rows) => rows.fold<int>(0, (sum, row) => sum + row.unread),
        orElse: () => 0,
      );
});

class MessagesScreen extends ConsumerStatefulWidget {
  const MessagesScreen({super.key});

  @override
  ConsumerState<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends ConsumerState<MessagesScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _open(ConversationSummary row) {
    final slug = row.groupId;
    if (slug != null && slug.isNotEmpty) {
      context.push('/groups/$slug/chat');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final feed = ref.watch(conversationsProvider);
    final rows = feed.maybeWhen(data: (r) => r, orElse: () => const <ConversationSummary>[]);
    final shown = _query.isEmpty
        ? rows
        : rows.where((r) => r.title.toLowerCase().contains(_query.toLowerCase())).toList();

    return Scaffold(
      backgroundColor: c.ground,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: c.accentText,
          onRefresh: () async => ref.invalidate(conversationsProvider),
          child: ListView(
            padding: const EdgeInsets.only(bottom: KoloSpace.section),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              KoloPageHeader(
                eyebrow: 'Messages',
                title: 'Conversations',
                actions: [
                  KoloIconAction(
                    icon: Icons.edit_outlined,
                    label: 'New message',
                    onTap: () => context.push('/groups'),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(KoloSpace.page, 6, KoloSpace.page, 0),
                child: KoloSearchField(
                  controller: _search,
                  hint: 'Search messages',
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              const SizedBox(height: 16),
              if (feed.isLoading && rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(KoloSpace.page),
                  child: Column(
                    children: [
                      for (var i = 0; i < 5; i++) ...[
                        const KoloSkeletonCard(),
                        const SizedBox(height: KoloSpace.md),
                      ],
                    ],
                  ),
                )
              else if (feed.hasError && rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: KoloSpace.page),
                  child: KoloEmptyState(
                    icon: Icons.cloud_off_rounded,
                    title: 'Messages are not loading',
                    message: 'Check your connection and pull down to try again.',
                    action: KoloTextAction(
                      label: 'Try again',
                      onTap: () => ref.invalidate(conversationsProvider),
                    ),
                  ),
                )
              else if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: KoloSpace.page),
                  child: KoloEmptyState(
                    icon: Icons.forum_outlined,
                    title: _query.isEmpty ? 'No conversations yet' : 'Nothing matches',
                    message: _query.isEmpty
                        ? 'Every group you join gets a conversation here.'
                        : 'Try a shorter search.',
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: KoloSpace.page),
                  child: KoloCard(
                    padding: EdgeInsets.zero,
                    elevated: true,
                    child: Column(
                      children: [
                        for (var i = 0; i < shown.length; i++)
                          _ConversationRow(
                            row: shown[i],
                            showDivider: i < shown.length - 1,
                            onTap: () => _open(shown[i]),
                          ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: KoloSpace.page),
                child: KoloNote(
                  icon: Icons.info_outline_rounded,
                  message:
                      'Push notifications are not wired in this build (G-02). Unread counts here are the only delivery signal a member gets.',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConversationRow extends StatelessWidget {
  const _ConversationRow({
    required this.row,
    required this.showDivider,
    required this.onTap,
  });

  final ConversationSummary row;
  final bool showDivider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final unread = row.unread > 0;
    final preview = row.lastBody.isEmpty
        ? 'No messages yet'
        : '${row.lastSender.isEmpty ? '' : '${row.lastSender}: '}${row.lastBody}';

    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 70),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: showDivider
              ? Border(bottom: BorderSide(color: c.hairlineSoft))
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: unread ? c.accent : c.surfaceSunken,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                row.initials,
                style: TextStyle(
                  fontFamily: KoloType.family,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                  color: unread ? c.accentOn : c.textSoft,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          row.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: KoloType.family,
                            fontSize: 14,
                            height: 1.45,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.112,
                            color: c.text,
                          ),
                        ),
                      ),
                      const SizedBox(width: KoloSpace.sm),
                      Text(
                        koloRelativeStamp(row.lastAt),
                        style: TextStyle(
                          fontFamily: KoloType.family,
                          fontSize: 11.5,
                          height: 1.4,
                          fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                          color: unread ? c.accentText : c.textFaint,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: KoloType.family,
                            fontSize: 12,
                            height: 1.4,
                            fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                            color: unread ? c.text : c.textSoft,
                          ),
                        ),
                      ),
                      if (unread) ...[
                        const SizedBox(width: KoloSpace.sm),
                        KoloCountBadge(count: row.unread),
                      ],
                    ],
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

String koloRelativeStamp(DateTime? at) {
  if (at == null) return '';
  final now = DateTime.now();
  final local = at.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return DateFormat('HH:mm').format(local);
  if (diff == 1) return 'Yesterday';
  if (diff < 7) return DateFormat('EEE').format(local);
  return DateFormat('d MMM').format(local);
}

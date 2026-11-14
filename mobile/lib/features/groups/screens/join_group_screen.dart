import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/providers.dart';
import '../../savings/savings_providers.dart';
import '../../../core/models/models.dart';
import '../../../design/components.dart';
import '../../../design/navigation.dart';
import '../../../design/tokens.dart';
import '../../../design/typography.dart';


class JoinGroupScreen extends ConsumerStatefulWidget {
  const JoinGroupScreen({super.key, this.invitationCode});

  /// Supplied by an invitation deep link. Pre-filling it means the member taps
  /// the link once instead of copying a code out of a chat message.
  final String? invitationCode;

  @override
  ConsumerState<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends ConsumerState<JoinGroupScreen> {
  final _search = TextEditingController();
  final _code = TextEditingController();
  List<GroupSummary> _results = const [];
  bool _busy = false;
  bool _searched = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final code = widget.invitationCode;
    if (code != null && code.isNotEmpty) {
      _code.text = code;
      // An invitation is the whole reason the member is here, so redeem it
      // rather than making them find the button.
      WidgetsBinding.instance.addPostFrameCallback((_) => _redeemCode());
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _redeemCode() async {
    final code = _code.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await ref.read(apiClientProvider).post(
        '/groups/invitations/accept/',
        body: {'token': code},
      );
      if (!mounted) return;
      ref.invalidate(myGroupsFreshProvider);
      final slug = data['slug'];
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        backgroundColor: context.colors.surface,
        builder: (sheetContext) => KoloSheet(
          title: 'You are in',
          subtitle: 'Welcome to ${data['name'] ?? 'the group'}.',
          actions: [
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  if (slug is String && slug.isNotEmpty) {
                    context.push('/groups/$slug');
                  } else {
                    context.pop();
                  }
                },
                child: const Text('Open group'),
              ),
            ),
          ],
          child: const SizedBox.shrink(),
        ),
      );
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.code == 'invitation_used' || error.code == 'invitation_invalid'
              ? 'That invitation is no longer valid. Ask an officer for a new one.'
              : error.userMessage;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runSearch() async {
    final term = _search.text.trim();
    if (term.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final rows = await ref.read(apiClientProvider).getList('/groups/', query: {'search': term});
      if (!mounted) return;
      setState(() {
        _results = rows.map(GroupSummary.fromJson).toList();
        _searched = true;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.userMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestJoin(GroupSummary group) async {
    setState(() => _busy = true);
    try {
      await ref.read(apiClientProvider).post('/groups/${group.slug}/join/', body: {
        'message': 'I would like to join ${group.name}.',
      });
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        backgroundColor: context.colors.surface,
        builder: (sheetContext) => KoloSheet(
          title: group.requiresApproval ? 'Request sent' : 'You have joined',
          subtitle: group.requiresApproval
              ? 'An officer of ${group.name} will review it. You will be notified when it '
                  'is approved — nothing to do until then.'
              : 'Welcome to ${group.name}.',
          actions: [
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(sheetContext),
                child: const Text('Okay'),
              ),
            ),
          ],
          child: const SizedBox.shrink(),
        ),
      );
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.userMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.colors;
    return Scaffold(
      backgroundColor: palette.ground,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  KoloSpace.page, KoloSpace.sm, KoloSpace.page, 0),
              child: Row(
                children: [
                  KoloBackButton(onTap: () => Navigator.of(context).maybePop()),
                  const Spacer(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  KoloSpace.page, KoloSpace.md, KoloSpace.page, 0),
              child: KoloPageHeader(
                eyebrow: 'An invitation is the fastest way in',
                title: 'Join a group',
              ),
            ),
            const SizedBox(height: KoloSpace.xl),

            // The code path first: an invitation is the more direct way in, and
            // the one a link delivers.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  KoloSpace.page, 0, KoloSpace.page, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('INVITATION CODE', style: KoloType.eyebrow(palette)),
                  const SizedBox(height: KoloSpace.sm),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _code,
                          textCapitalization: TextCapitalization.characters,
                          onSubmitted: (_) => _redeemCode(),
                          style: TextStyle(
                            fontFamily: KoloType.family,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                            color: palette.text,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Paste the code an officer sent',
                          ),
                        ),
                      ),
                      const SizedBox(width: KoloSpace.sm),
                      SizedBox(
                        height: 56,
                        child: FilledButton(
                          onPressed: _busy ? null : _redeemCode,
                          child: const Text('Join'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: KoloSpace.xl),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: KoloSpace.page),
              child: Row(
                children: [
                  Expanded(child: Divider(color: palette.hairline)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: KoloSpace.md),
                    child: Text('or find one', style: Theme.of(context).textTheme.bodySmall),
                  ),
                  Expanded(child: Divider(color: palette.hairline)),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(
                  KoloSpace.page, KoloSpace.lg, KoloSpace.page, 0),
              child: TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _runSearch(),
                style: TextStyle(fontFamily: KoloType.family, fontSize: 15.5,
                    color: palette.text),
                decoration: InputDecoration(
                  hintText: 'Search by group name',
                  prefixIcon: Icon(Icons.search_rounded, color: palette.textFaint, size: 20),
                  suffixIcon: IconButton(
                    tooltip: 'Search groups',
                    icon: const Icon(Icons.arrow_forward_rounded, size: 19),
                    onPressed: _busy ? null : _runSearch,
                  ),
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    KoloSpace.page, KoloSpace.md, KoloSpace.page, 0),
                child: KoloNotice(
                  message: _error!,
                  tone: KoloNoticeTone.critical,
                  icon: Icons.error_outline_rounded,
                ),
              ),
            Expanded(
              child: _busy && _results.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                      ? KoloEmptyState(
                          icon: Icons.search_off_rounded,
                          title: _searched ? 'No groups matched' : 'Find your people',
                          message: _searched
                              ? 'Try a different name, or ask an officer for an invite link. '
                                  'Private groups never appear in search — that is the point of '
                                  'being private.'
                              : 'Search for a group you have been invited to, or start your own.',
                          action: OutlinedButton(
                            onPressed: () => context.push('/groups/new'),
                            child: const Text('Start a group'),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(
                              KoloSpace.page, KoloSpace.lg, KoloSpace.page, KoloSpace.hero),
                          itemCount: _results.length,
                          separatorBuilder: (_, __) => const SizedBox(height: KoloSpace.sm + 2),
                          itemBuilder: (context, index) {
                            final group = _results[index];
                            return KoloCard(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(group.name,
                                            style: Theme.of(context).textTheme.titleMedium,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis),
                                        const SizedBox(height: 3),
                                        Text(
                                          '${group.memberCount} members · ${koloHumanise(group.category)}',
                                          style: Theme.of(context).textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: KoloSpace.sm),
                                  SizedBox(
                                    height: 44,
                                    child: FilledButton(
                                      onPressed: _busy ? null : () => _requestJoin(group),
                                      child: Text(group.requiresApproval ? 'Request' : 'Join'),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/providers.dart';
import '../../savings/savings_providers.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/kolo_theme.dart';
import '../../../shared/widgets/common.dart';

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
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('You are in'),
          content: Text('Welcome to ${data['name'] ?? 'the group'}.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                if (slug is String && slug.isNotEmpty) {
                  context.push('/groups/$slug');
                } else {
                  context.pop();
                }
              },
              child: const Text('Open group'),
            ),
          ],
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
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Request sent'),
          content: Text(
            group.requiresApproval
                ? 'An officer of ${group.name} will review your request. You will be notified when '
                    'it is approved.'
                : 'You have joined ${group.name}.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Okay')),
          ],
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
    final palette = context.kolo;
    return Scaffold(
      appBar: AppBar(title: const Text('Join a group')),
      body: SafeArea(
        child: Column(
          children: [
            // The code path first: an invitation is the more direct way in, and
            // the one a link delivers.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _code,
                      textCapitalization: TextCapitalization.characters,
                      onSubmitted: (_) => _redeemCode(),
                      decoration: const InputDecoration(
                        labelText: 'Invitation code',
                        hintText: 'Paste the code an officer sent you',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.tonal(
                    onPressed: _busy ? null : _redeemCode,
                    child: const Text('Join'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _runSearch(),
                decoration: InputDecoration(
                  hintText: 'Search by group name',
                  prefixIcon: Icon(Icons.search, color: palette.textFaint),
                  suffixIcon: IconButton(
                    tooltip: 'Search groups',
                    icon: const Icon(Icons.arrow_forward_rounded),
                    onPressed: _busy ? null : _runSearch,
                  ),
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ErrorNotice(error: ApiException(code: 'search', message: _error!)),
              ),
            Expanded(
              child: _busy && _results.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                      ? EmptyState(
                          icon: Icons.search_off_rounded,
                          title: _searched ? 'No groups matched' : 'Find your people',
                          message: _searched
                              ? 'Try a different name, or ask an officer for an invite link. '
                                  'Private groups never appear in search.'
                              : 'Search for a group you have been invited to, or start your own.',
                          action: FilledButton.tonal(
                            onPressed: () => context.push('/groups/new'),
                            child: const Text('Start a group'),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                          itemCount: _results.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
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
                                            style: Theme.of(context).textTheme.titleMedium),
                                        const SizedBox(height: 3),
                                        Text(
                                          '${group.memberCount} members · ${humanise(group.category)}',
                                          style: Theme.of(context).textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  FilledButton.tonal(
                                    onPressed: _busy ? null : () => _requestJoin(group),
                                    child: Text(group.requiresApproval ? 'Request' : 'Join'),
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

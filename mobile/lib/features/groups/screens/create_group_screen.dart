import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/providers.dart';
import '../../../core/theme/kolo_theme.dart';
import '../../../shared/widgets/common.dart';
import '../../savings/savings_providers.dart';

class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  String _visibility = 'restricted';
  final String _category = 'friends';
  String _currency = 'NGN';
  bool _requiresApproval = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final data = await ref.read(apiClientProvider).post('/groups/', body: {
        'name': _name.text.trim(),
        'description': _description.text.trim(),
        'visibility': _visibility,
        'category': _category,
        'currency': _currency,
        'requires_approval': _requiresApproval,
      });
      ref.invalidate(myGroupsProvider);
      if (!mounted) return;
      final slug = '${data['slug'] ?? ''}';
      if (slug.isNotEmpty) {
        context.pushReplacement('/groups/$slug');
      } else {
        context.go('/');
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.userMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.kolo;
    return Scaffold(
      appBar: AppBar(title: const Text('New group')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_error != null) ...[
                  ErrorNotice(error: ApiException(code: 'group', message: _error!)),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Group name',
                    hintText: 'e.g. Abuja Friends Ajo',
                  ),
                  validator: (value) =>
                      (value == null || value.trim().length < 3) ? 'Give the group a name' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _description,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'What is this group for?',
                    hintText: 'Optional — helps members recognise it',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 22),
                Text('Who can find this group?', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                _ChoiceTile(
                  selected: _visibility == 'private',
                  title: 'Invite only',
                  subtitle: 'Only people you add can see it exists.',
                  icon: Icons.lock_outline_rounded,
                  onTap: () => setState(() => _visibility = 'private'),
                ),
                const SizedBox(height: 8),
                _ChoiceTile(
                  selected: _visibility == 'restricted',
                  title: 'Discoverable, approval needed',
                  subtitle: 'People can find it and ask to join; you approve each one.',
                  icon: Icons.group_outlined,
                  onTap: () => setState(() => _visibility = 'restricted'),
                ),
                const SizedBox(height: 8),
                _ChoiceTile(
                  selected: _visibility == 'public',
                  title: 'Open',
                  subtitle: 'Anyone can see and join. Rarely right for money.',
                  icon: Icons.public,
                  onTap: () => setState(() => _visibility = 'public'),
                ),
                const SizedBox(height: 22),
                Text('Currency', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final code in ['NGN', 'USD', 'GBP', 'KES', 'GHS', 'ZAR'])
                      ChoiceChip(
                        label: Text(code),
                        selected: _currency == code,
                        onSelected: (_) => setState(() => _currency = code),
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                SwitchListTile.adaptive(
                  value: _requiresApproval,
                  onChanged: (value) => setState(() => _requiresApproval = value),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Approve new members'),
                  subtitle: const Text('Recommended: a savings group is only as safe as its members.'),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: palette.moneySoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.shield_outlined, size: 18, color: palette.warning),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'You will be the owner. Withdrawals will need a second officer to '
                          'approve them, and you cannot approve a payout to yourself.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: palette.text,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Create group'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.selected,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.kolo;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? palette.accent : palette.divider,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: selected ? palette.accent : palette.textFaint),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: selected ? palette.accent : palette.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle, size: 20, color: palette.accent),
          ],
        ),
      ),
    );
  }
}

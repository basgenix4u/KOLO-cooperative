import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/providers.dart';
import '../../../design/components.dart';
import '../../../design/navigation.dart';
import '../../../design/tokens.dart';
import '../../../design/typography.dart';
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
    final palette = context.colors;
    return Scaffold(
      backgroundColor: palette.ground,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
              KoloSpace.page, KoloSpace.sm, KoloSpace.page, KoloSpace.hero),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    KoloBackButton(onTap: () => Navigator.of(context).maybePop()),
                    const Spacer(),
                  ],
                ),
                const SizedBox(height: KoloSpace.md),
                KoloPageHeader(
                  eyebrow: 'You will be the owner',
                  title: 'Start a group',
                ),
                const SizedBox(height: KoloSpace.xl),
                if (_error != null) ...[
                  KoloNotice(
                    message: _error!,
                    tone: KoloNoticeTone.critical,
                    icon: Icons.error_outline_rounded,
                  ),
                  const SizedBox(height: KoloSpace.lg),
                ],
                Text('NAME', style: KoloType.eyebrow(palette)),
                const SizedBox(height: KoloSpace.sm),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  style: TextStyle(
                    fontFamily: KoloType.family, fontSize: 16,
                    fontWeight: FontWeight.w500, color: palette.text,
                  ),
                  decoration: const InputDecoration(hintText: 'e.g. Abuja Friends Ajo'),
                  validator: (value) =>
                      (value == null || value.trim().length < 3) ? 'Give the group a name' : null,
                ),
                const SizedBox(height: KoloSpace.lg),
                Text('WHAT IS IT FOR', style: KoloType.eyebrow(palette)),
                const SizedBox(height: KoloSpace.sm),
                TextFormField(
                  controller: _description,
                  maxLines: 3,
                  style: TextStyle(
                    fontFamily: KoloType.family, fontSize: 15, color: palette.text,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Optional — helps members recognise it',
                  ),
                ),
                const SizedBox(height: KoloSpace.section),
                Text('Who can find this group?', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: KoloSpace.md),
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
                const SizedBox(height: KoloSpace.section),
                Text('Currency', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: KoloSpace.md),
                Wrap(
                  spacing: KoloSpace.sm,
                  runSpacing: KoloSpace.sm,
                  children: [
                    for (final code in ['NGN', 'USD', 'GBP', 'KES', 'GHS', 'ZAR'])
                      ChoiceChip(
                        label: Text(code),
                        selected: _currency == code,
                        onSelected: (_) => setState(() => _currency = code),
                      ),
                  ],
                ),
                const SizedBox(height: KoloSpace.section),
                KoloCard(
                  padding: const EdgeInsets.symmetric(
                      horizontal: KoloSpace.lg, vertical: KoloSpace.xs),
                  child: Material(
                    color: Colors.transparent,
                    child: SwitchListTile.adaptive(
                      value: _requiresApproval,
                      onChanged: (value) => setState(() => _requiresApproval = value),
                      contentPadding: EdgeInsets.zero,
                      title: Text('Approve new members',
                          style: Theme.of(context).textTheme.titleSmall),
                      subtitle: Text(
                        'A savings group is only as safe as its members.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: KoloSpace.lg),
                KoloNotice(
                  message: 'Withdrawals will need a second officer to approve them, and '
                      'you cannot approve a payout to yourself — not even as the owner.',
                  tone: KoloNoticeTone.warning,
                  icon: Icons.shield_outlined,
                ),
                const SizedBox(height: KoloSpace.xl),
                KoloSubmitButton(
                  label: 'Create group',
                  busyLabel: 'Creating…',
                  busy: _busy,
                  onPressed: _submit,
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
    final c = context.colors;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KoloRadius.md),
        child: AnimatedContainer(
          duration: KoloMotion.fast,
          padding: const EdgeInsets.all(KoloSpace.lg),
          decoration: BoxDecoration(
            // The selected option takes a citrus tint and a citrus edge; the
            // unselected ones stay quiet. Citrus is for selection, not for
            // every surface that happens to be tappable.
            color: selected ? c.accentWash : c.surface,
            borderRadius: BorderRadius.circular(KoloRadius.md),
            border: Border.all(
              color: selected ? c.accent : c.hairline,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 19, color: selected ? c.accentText : c.textSoft),
              const SizedBox(width: KoloSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: context.text.titleSmall?.copyWith(
                        color: c.text, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(subtitle, style: context.text.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: KoloSpace.sm),
              // Selection is a filled circle, not only a colour: the tick is the
              // signal, the colour reinforces it.
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 20,
                color: selected ? c.accentText : c.textFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

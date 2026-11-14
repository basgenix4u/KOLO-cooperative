import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/models/models.dart';
import '../../../core/models/money.dart';
import '../../../design/components.dart';
import '../../../design/navigation.dart';
import '../../../design/tokens.dart';
import '../../../design/typography.dart';
import '../savings_providers.dart';

/// Paying a contribution.
///
/// The rule this screen is built around: nothing is paid until the provider says
/// it is. The app never shows "paid" because a button was pressed, and the
/// four payment states are always distinguishable — started, waiting on the
/// provider, confirmed, and failed. A member must never be left guessing which
/// one they are in.
///
/// The flow has three steps and the member can always see which one they are on:
///   amount  →  checkout created  →  confirmed
class ContributeScreen extends ConsumerStatefulWidget {
  const ContributeScreen({
    super.key,
    required this.programmeId,
    this.obligationId,
    this.suggestedMinor,
  });

  final String programmeId;
  final String? obligationId;
  final int? suggestedMinor;

  @override
  ConsumerState<ContributeScreen> createState() => _ContributeScreenState();
}

class _ContributeScreenState extends ConsumerState<ContributeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountFocus = FocusNode();
  late final TextEditingController _amount;
  late final String _currency;
  bool _busy = false;
  String? _error;
  ({String reference, String checkoutUrl})? _started;
  bool _confirmed = false;

  @override
  void initState() {
    super.initState();
    _currency = ref.read(programmeProvider(widget.programmeId)).value?.currency ?? 'NGN';
    final suggested = widget.suggestedMinor;
    _amount = TextEditingController(
      // Run the prefill through the same grouping as typed input. Otherwise the
      // suggested amount reads "50000.00" while anything typed reads "50,000.00"
      // — two representations of the same money on one screen.
      text: suggested == null ? '' : groupMinorUnits(suggested),
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  Money? get _parsed => Money.tryParse(_amount.text, _currency);

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final parsed = _parsed;
    if (parsed == null || parsed.minor <= 0) {
      setState(() => _error = 'Enter an amount greater than zero.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final result = await ref.read(moneyActionsProvider).contribute(
            programmeId: widget.programmeId,
            amountMinor: parsed.minor,
            obligationId: widget.obligationId,
          );
      if (!mounted) return;
      setState(() => _started = (reference: result.reference, checkoutUrl: result.checkoutUrl));
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendly(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkPayment() async {
    final started = _started;
    if (started == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final status = await ref.read(moneyActionsProvider).verifyPayment(started.reference);
      if (!mounted) return;
      if (status == 'succeeded' || status == 'confirmed') {
        ref.invalidate(myContributionsProvider);
        ref.invalidate(myObligationsProvider);
        ref.invalidate(groupProgrammesProvider);
        setState(() => _confirmed = true);
      } else {
        setState(() => _error =
            'The provider has not confirmed this payment yet. If you completed the '
            'checkout, give it a moment and check again. Nothing is lost — the '
            'reference above is how it is matched.');
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = _friendly(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendly(ApiException error) {
    switch (error.code) {
      case 'insufficient_funds':
        return 'That payment did not go through — the account it came from had '
            'insufficient funds. Try again or use another method.';
      case 'overpayment':
      case 'amount_exceeds_obligation':
        return 'That is more than you owe on this programme. Pay the outstanding '
            'amount, or ask an officer to record the extra.';
      case 'programme_transition_invalid':
        return 'This programme is not accepting contributions right now.';
      case 'not_a_member':
        return 'You are not a member of this group any more, so you cannot pay into it.';
      case 'network_error':
      case 'timeout':
        return 'KOLO could not be reached. Your payment was not started. Check your '
            'connection and try again.';
      default:
        return error.userMessage;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final programme = ref.watch(programmeProvider(widget.programmeId)).value;

    return Scaffold(
      backgroundColor: c.ground,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  KoloSpace.page, KoloSpace.sm, KoloSpace.page, 0),
              child: Row(
                children: [
                  KoloBackButton(
                    onTap: () => context.canPop() ? context.pop() : context.go('/money'),
                  ),
                  const Spacer(),
                  _StepDots(
                    // Three steps, three dots. The member can always see how far
                    // through the payment they are.
                    current: _confirmed ? 3 : (_started == null ? 1 : 2),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                    KoloSpace.page, KoloSpace.xl, KoloSpace.page, KoloSpace.hero),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: KoloSpace.maxContent),
                    // Explicitly typed: the router handed this screen a
                    // programme, and the form always renders something.
                    child: switch (true) {
                      _ when _confirmed => _Confirmed(reference: _started!.reference),
                      _ when _started != null => _awaitingPayment(context),
                      _ => _amountForm(context, programme),
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _amountForm(BuildContext context, Programme? programme) {
    final c = context.colors;
    final parsed = _parsed;
    final owed = widget.suggestedMinor;
    final isFullOwed = owed != null && parsed != null && parsed.minor == owed;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            programme?.name ?? 'Contribution',
            style: context.text.titleMedium?.copyWith(color: c.textSoft),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: KoloSpace.xs),
          Text('How much are you paying?', style: context.text.headlineSmall),
          const SizedBox(height: KoloSpace.xl + 4),

          // The amount field is the hero of this screen. It is set large, with
          // the currency mark part of the input rather than a label beside it,
          // because that is the one number the member is deciding.
          Text('AMOUNT', style: KoloType.eyebrow(c)),
          const SizedBox(height: KoloSpace.sm),
          TextFormField(
            controller: _amount,
            focusNode: _amountFocus,
            autofocus: owed == null,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: const [AmountGroupingFormatter()],
            onChanged: (_) => setState(() {}),
            style: KoloType.money(c, size: 34, weight: FontWeight.w700),
            decoration: InputDecoration(
              prefixText: '${Money.symbolFor(_currency)}\u2009\u2009',
              // Shares the input's baseline automatically, so only the size and
              // tone need setting. The glyph carries its own sidebearing, so no
              // extra spacing is added here.
              prefixStyle: TextStyle(
                fontFamily: KoloType.family,
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: c.textSoft,
              ),
              hintText: '0.00',
              hintStyle: KoloType.money(c, size: 34, weight: FontWeight.w700, color: c.textFaint),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: KoloSpace.lg, vertical: KoloSpace.lg + 4),
            ),
            validator: (value) {
              final p = Money.tryParse(value ?? '', _currency);
              if (p == null) return 'Enter an amount';
              if (p.minor <= 0) return 'Enter an amount greater than zero';
              return null;
            },
          ),

          // Paying the exact outstanding amount is the common case, so it gets a
          // one-tap shortcut rather than asking the member to retype a figure the
          // app already knows.
          if (owed != null && owed > 0) ...[
            const SizedBox(height: KoloSpace.md),
            Wrap(
              spacing: KoloSpace.sm,
              runSpacing: KoloSpace.sm,
              children: [
                _AmountChip(
                  label: 'Full amount · ${Money(owed, _currency).format()}',
                  selected: isFullOwed,
                  onTap: () => setState(() {
                    _amount.text = groupMinorUnits(owed);
                    _error = null;
                  }),
                ),
                _AmountChip(
                  label: 'Half · ${Money(owed ~/ 2, _currency).format()}',
                  selected: parsed != null && parsed.minor == owed ~/ 2,
                  onTap: () => setState(() {
                    _amount.text = groupMinorUnits(owed ~/ 2);
                    _error = null;
                  }),
                ),
              ],
            ),
          ],

          if (_error != null) ...[
            const SizedBox(height: KoloSpace.lg),
            KoloNotice(
              message: _error!,
              tone: KoloNoticeTone.critical,
              icon: Icons.error_outline_rounded,
            ),
          ],

          const SizedBox(height: KoloSpace.xl),

          // Say plainly what happens next and who confirms it. This is the
          // moment a member decides whether to trust the app with money.
          KoloNotice(
            message: 'You will be sent to a secure checkout. Your contribution only '
                'counts once the payment provider confirms it — KOLO never records money '
                'on your word, and never on ours.',
            tone: KoloNoticeTone.neutral,
            icon: Icons.lock_outline_rounded,
          ),

          const SizedBox(height: KoloSpace.xl),
          KoloSubmitButton(
            label: parsed == null ? 'Continue to payment' : 'Pay ${parsed.format()}',
            busyLabel: 'Starting checkout…',
            busy: _busy,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }

  Widget _awaitingPayment(BuildContext context) {
    final c = context.colors;
    final started = _started!;
    final parsed = _parsed;
    final amount = parsed ?? Money(0, _currency);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: c.pendingWash,
            borderRadius: BorderRadius.circular(KoloRadius.lg),
          ),
          child: Icon(Icons.hourglass_top_rounded, size: 26, color: c.pending),
        ),
        const SizedBox(height: KoloSpace.lg),
        Text('Waiting on the payment', style: context.text.headlineSmall),
        const SizedBox(height: KoloSpace.sm),
        Text(
          'A checkout has been opened for ${amount.format()}. Complete it there, then '
          'come back. This screen is the only place that decides whether it worked.',
          style: context.text.bodyMedium?.copyWith(color: c.textSoft, height: 1.5),
        ),
        const SizedBox(height: KoloSpace.xl),

        // State this loudly: the money is not counted yet. Showing a success tick
        // here would be the single most damaging lie the app could tell.
        KoloNotice(
          message: 'Not counted yet. Your group will not see this as paid until the '
              'provider confirms it.',
          tone: KoloNoticeTone.warning,
          icon: Icons.schedule_rounded,
        ),

        const SizedBox(height: KoloSpace.lg),
        KoloCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('REFERENCE', style: KoloType.eyebrow(c)),
              const SizedBox(height: KoloSpace.sm),
              SelectableText(
                started.reference,
                style: TextStyle(
                  fontFamily: KoloType.family,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: c.text,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: KoloSpace.sm),
              Text(
                'Quote this to your officers if anything looks wrong. It is how a '
                'payment is matched to you.',
                style: context.text.bodySmall,
              ),
            ],
          ),
        ),

        if (_error != null) ...[
          const SizedBox(height: KoloSpace.lg),
          KoloNotice(
            message: _error!,
            tone: KoloNoticeTone.warning,
            icon: Icons.info_outline_rounded,
          ),
        ],

        const SizedBox(height: KoloSpace.xl),
        KoloSubmitButton(
          label: 'I have paid — check now',
          busyLabel: 'Checking with the provider…',
          busy: _busy,
          onPressed: _checkPayment,
        ),
        const SizedBox(height: KoloSpace.md),
        SizedBox(
          height: 50,
          child: OutlinedButton(
            onPressed: _busy ? null : () => context.pop(),
            child: const Text('Back to programme'),
          ),
        ),
      ],
    );
  }
}

/// The one screen in the app that is allowed to be celebratory, and even here it
/// states the reference rather than a vague "success".
class _Confirmed extends StatelessWidget {
  const _Confirmed({required this.reference});

  final String reference;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: KoloSpace.section),
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: c.settledWash,
            borderRadius: BorderRadius.circular(KoloRadius.xl),
          ),
          child: Icon(Icons.check_rounded, size: 32, color: c.settled),
        ),
        const SizedBox(height: KoloSpace.lg),
        Text('Payment confirmed', style: context.text.headlineSmall),
        const SizedBox(height: KoloSpace.sm),
        Text(
          'The provider confirmed it, so this is now part of the group’s records.',
          style: context.text.bodyMedium?.copyWith(color: c.textSoft, height: 1.5),
        ),
        const SizedBox(height: KoloSpace.lg),
        KoloCard(
          child: Row(
            children: [
              Text('REFERENCE', style: KoloType.eyebrow(c)),
              const Spacer(),
              SelectableText(
                reference,
                style: KoloType.money(c, size: 14, weight: FontWeight.w700),
              ),
            ],
          ),
        ),
        const SizedBox(height: KoloSpace.xl),
        KoloSubmitButton(
          label: 'Done',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/money');
            }
          },
        ),
      ],
    );
  }
}

/// Three dots, one per step. Kept to dots rather than a labelled stepper: the
/// screen already says what it wants, and a stepper would compete with it.
class _StepDots extends StatelessWidget {
  const _StepDots({required this.current});

  final int current;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: 'Step $current of 3',
      child: Row(
        children: [
          for (var i = 1; i <= 3; i++) ...[
            AnimatedContainer(
              duration: KoloMotion.fast,
              width: i == current ? 18 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: i <= current ? c.text : c.hairline,
                borderRadius: BorderRadius.circular(KoloRadius.full),
              ),
            ),
            if (i < 3) const SizedBox(width: KoloSpace.xs + 1),
          ],
        ],
      ),
    );
  }
}

class _AmountChip extends StatelessWidget {
  const _AmountChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KoloRadius.full),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: KoloSpace.md, vertical: KoloSpace.sm + 2),
          decoration: BoxDecoration(
            color: selected ? c.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(KoloRadius.full),
            border: Border.all(
              color: selected ? c.accent : c.hairline,
              width: 1.2,
            ),
          ),
          child: Text(
            label,
            style: context.text.labelMedium?.copyWith(
              color: selected ? c.accentOn : c.text,
            ),
          ),
        ),
      ),
    );
  }
}


/// Formats minor units the way [AmountGroupingFormatter] does, for values that
/// arrive from the server rather than from the keyboard.
String groupMinorUnits(int minor) {
  final negative = minor < 0;
  final abs = minor.abs();
  final whole = (abs ~/ 100).toString();
  final fraction = (abs % 100).toString().padLeft(2, '0');
  final buffer = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buffer.write(',');
    buffer.write(whole[i]);
  }
  return '${negative ? '-' : ''}$buffer.$fraction';
}

/// Groups thousands as the member types, without moving their caret.
///
/// An amount shown as "50000.00" has to be counted digit by digit to be checked.
/// "50,000.00" reads at a glance — which matters when the next thing that happens
/// is money leaving an account. Grouping is done here rather than at display time
/// so what is on screen is exactly what will be parsed.
class AmountGroupingFormatter extends TextInputFormatter {
  const AmountGroupingFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text;

    // How many digits sat before the caret? Restoring that count afterwards
    // keeps the caret where the member left it instead of jumping to the end.
    final caret = newValue.selection.baseOffset.clamp(0, raw.length);
    final digitsBeforeCaret =
        raw.substring(0, caret).replaceAll(RegExp(r'[^0-9]'), '').length;

    // Split into the whole part and anything after a decimal point.
    final cleaned = raw.replaceAll(RegExp(r'[^0-9.]'), '');
    final dot = cleaned.indexOf('.');
    var whole = dot == -1 ? cleaned : cleaned.substring(0, dot);
    final fraction = dot == -1 ? null : cleaned.substring(dot + 1);

    // Only one decimal point, and never more than two decimal places.
    final safeFraction = fraction == null
        ? null
        : fraction.replaceAll('.', '').substring(
            0, fraction.replaceAll('.', '').length.clamp(0, 2));

    // Leading zeros are noise, but a lone zero before a decimal point is not.
    whole = whole.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (whole.isEmpty && (safeFraction == null || safeFraction.isEmpty)) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    final buffer = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) buffer.write(',');
      buffer.write(whole[i]);
    }
    if (safeFraction != null) {
      buffer.write('.');
      buffer.write(safeFraction);
    }
    final formatted = buffer.toString();

    // Walk the formatted string until the same number of digits has been passed.
    var seen = 0;
    var newCaret = formatted.length;
    for (var i = 0; i < formatted.length; i++) {
      if (seen == digitsBeforeCaret) {
        newCaret = i;
        break;
      }
      if (RegExp(r'[0-9]').hasMatch(formatted[i])) seen++;
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(
        offset: newCaret.clamp(0, formatted.length),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/models/money.dart';
import '../../../core/theme/kolo_theme.dart';
import '../../../shared/widgets/common.dart';
import '../savings_providers.dart';

/// Paying a contribution.
///
/// The screen is explicit that nothing has been paid until the provider
/// confirms it. The app never shows "paid" because a button was pressed.
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
  late final TextEditingController _amount;
  late final String _currency;
  bool _busy = false;
  String? _error;
  ({String reference, String checkoutUrl})? _started;

  @override
  void initState() {
    super.initState();
    _currency = ref.read(programmeProvider(widget.programmeId)).valueOrNull?.currency ?? 'NGN';
    final suggested = widget.suggestedMinor;
    _amount = TextEditingController(
      text: suggested == null ? '' : (suggested / 100).toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final parsed = Money.tryParse(_amount.text, _currency);
    if (parsed == null || parsed.minor <= 0) {
      setState(() => _error = 'Enter a valid amount.');
      return;
    }

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
      setState(() => _error = error.userMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkPayment() async {
    final started = _started;
    if (started == null) return;
    setState(() => _busy = true);
    try {
      final status = await ref.read(moneyActionsProvider).verifyPayment(started.reference);
      if (!mounted) return;
      ref.invalidate(myContributionsProvider);
      ref.invalidate(myObligationsProvider);
      ref.invalidate(groupProgrammesProvider);

      if (status == 'succeeded') {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Contribution confirmed'),
            content: Text(
              'Your payment was confirmed by the provider. Reference ${started.reference}.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  context.pop();
                },
                child: const Text('Done'),
              ),
            ],
          ),
        );
      } else {
        setState(() => _error =
            'The provider has not confirmed this payment yet. If you completed it, give it a '
            'moment and check again.');
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.userMessage);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final programme = ref.watch(programmeProvider(widget.programmeId)).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Contribute')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: _started == null ? _amountForm(context, programme) : _awaitingPayment(context),
        ),
      ),
    );
  }

  Widget _amountForm(BuildContext context, programme) {

    final palette = context.kolo;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            programme?.name ?? 'Contribution',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            programme != null
                ? 'This month\'s contribution is ${programme.contributionAmount.format()}'
                : 'Enter the amount you are paying',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          if (_error != null) ...[
            ErrorNotice(error: ApiException(code: 'contribute', message: _error!)),
            const SizedBox(height: 16),
          ],
          TextFormField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.5),
            decoration: InputDecoration(
              prefixText: '${Money.symbolFor(_currency)} ',
              prefixStyle: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: palette.text,
              ),
              hintText: '0.00',
            ),
            validator: (value) {
              final parsed = Money.tryParse(value ?? '', _currency);
              if (parsed == null) return 'Enter an amount';
              if (parsed.minor <= 0) return 'Enter an amount greater than zero';
              return null;
            },
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: palette.ground,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 16, color: palette.textFaint),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'You will be sent to a secure checkout. Your contribution only counts once '
                    'the payment provider confirms it — KOLO never records money on your word.',
                    style: Theme.of(context).textTheme.bodySmall,
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
                : const Text('Continue to payment'),
          ),
        ],
      ),
    );
  }

  Widget _awaitingPayment(BuildContext context) {

    final palette = context.kolo;
    final started = _started!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: palette.moneySoft, shape: BoxShape.circle),
          child: Icon(Icons.hourglass_top_rounded, color: palette.warning),
        ),
        const SizedBox(height: 18),
        Text('Awaiting payment', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'A checkout has been created. Complete the payment there, then come back and check.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        KoloCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Reference', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              SelectableText(
                started.reference,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Quote this reference to support if anything looks wrong.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          ErrorNotice(error: ApiException(code: 'verify', message: _error!)),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _checkPayment,
          child: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('I have paid — check now'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: () => context.pop(),
          child: const Text('Back to programme'),
        ),
      ],
    );
  }
}

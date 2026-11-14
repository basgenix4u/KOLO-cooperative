import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../design/components.dart';
import '../../../design/tokens.dart';
import '../../../design/typography.dart';
import '../auth_controller.dart';
import 'auth_scaffold.dart';

/// Verifying proves the member controls the address. Until then the account
/// exists but cannot receive or send money, which is why this screen is a wall,
/// not a nag.
class VerifyScreen extends ConsumerStatefulWidget {
  const VerifyScreen({super.key, required this.email});

  final String email;

  @override
  ConsumerState<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends ConsumerState<VerifyScreen> {
  final _code = TextEditingController();
  Timer? _countdown;
  int _cooldown = 0;
  bool _busy = false;
  bool _resending = false;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    // The first code was sent moments ago in RegisterScreen, so the resend
    // starts on cooldown rather than inviting an immediate duplicate.
    _startCooldown(30);
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _startCooldown(int seconds) {
    _countdown?.cancel();
    setState(() => _cooldown = seconds);
    _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _cooldown = _cooldown > 0 ? _cooldown - 1 : 0);
      if (_cooldown == 0) timer.cancel();
    });
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length < 4) {
      setState(() => _error = 'Enter the full code from your email.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(authControllerProvider).verifyCode(code: code);
      if (!mounted) return;
      // Verification needs a session; registration does not sign the member in,
      // so anything other than an existing session lands on sign-in.
      context.go('/login');
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendly(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    if (_cooldown > 0 || _resending) return;
    setState(() {
      _resending = true;
      _error = null;
      _notice = null;
    });
    try {
      await ref.read(authControllerProvider).requestCode(channel: 'email');
      if (!mounted) return;
      setState(() => _notice = 'A new code is on its way to ${widget.email}.');
      _startCooldown(60);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = _friendly(error));
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  String _friendly(ApiException error) {
    switch (error.code) {
      case 'invalid_code':
      case 'code_invalid':
        return 'That code is not right. Check the six digits and try again.';
      case 'code_expired':
        return 'That code has expired. Send a new one.';
      case 'too_many_attempts':
        return 'Too many tries. Wait a few minutes before asking for another code.';
      case 'network_error':
      case 'timeout':
        return 'We could not reach KOLO. Check your connection and try again.';
      default:
        return error.userMessage;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AuthScaffold(
      title: 'Confirm your email',
      subtitle: 'We sent a six-digit code to ${widget.email}. '
          'Entering it proves the address is yours.',
      showBack: true,
      error: _error == null ? null : AuthError(message: _error!),
      notice: _notice == null
          ? null
          : KoloNotice(
              message: _notice!,
              tone: KoloNoticeTone.positive,
              icon: Icons.mark_email_read_outlined,
            ),
      children: [
        Text('YOUR CODE', style: KoloType.eyebrow(c).copyWith(color: c.textSoft)),
        const SizedBox(height: KoloSpace.sm),
        CodeField(
          controller: _code,
          enabled: !_busy,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onComplete: (_) => _verify(),
        ),
        const SizedBox(height: KoloSpace.xl),
        KoloSubmitButton(
          label: 'Confirm email',
          busyLabel: 'Confirming…',
          busy: _busy,
          onPressed: _verify,
        ),
        const SizedBox(height: KoloSpace.lg),
        Center(
          child: TextButton(
            onPressed: (_cooldown > 0 || _resending) ? null : _resend,
            child: Text(
              _resending
                  ? 'Sending…'
                  : _cooldown > 0
                      ? 'Send a new code in ${_cooldown}s'
                      : 'Send a new code',
            ),
          ),
        ),
        const SizedBox(height: KoloSpace.xxl),
        _WhyThisMatters(),
      ],
    );
  }
}

/// Explains the gate rather than leaving the member to guess why a screen is
/// standing between them and the app. A wall without a reason is a wall people
/// try to climb.
class _WhyThisMatters extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return KoloCard(
      padding: const EdgeInsets.all(KoloSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, size: 15, color: c.textSoft),
              const SizedBox(width: KoloSpace.sm),
              Text(
                'WHY THIS STEP EXISTS',
                style: KoloType.eyebrow(c),
              ),
            ],
          ),
          const SizedBox(height: KoloSpace.md),
          Text(
            'A confirmed address is how your group reaches you about payouts, '
            'and how you recover an account. Cards and codes cannot hold money '
            'in KOLO until this is done — for everyone’s protection, including yours.',
            style: context.text.bodySmall?.copyWith(color: c.textSoft, height: 1.5),
          ),
        ],
      ),
    );
  }
}

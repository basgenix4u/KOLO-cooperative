import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../design/components.dart';
import '../../../design/tokens.dart';
import '../../../design/typography.dart';
import '../auth_controller.dart';
import 'auth_scaffold.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _obscure = true;
  bool _remember = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(authControllerProvider).login(
            identifier: _identifier.text,
            password: _password.text,
          );
      if (!mounted) return;
      context.go('/');
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendly(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Sign-in failures get one message. Saying "no account with that email"
  /// turns the form into a way to discover who banks here.
  String _friendly(ApiException error) {
    switch (error.code) {
      case 'invalid_credentials':
      case 'no_active_account':
      case 'authentication_failed':
        return 'That email or password did not match. Try again, or reset your password.';
      case 'account_locked':
        return 'Too many attempts. Wait a few minutes, then try again.';
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
      title: 'Welcome back',
      subtitle: 'Sign in to see what your group owes and what is owed to you.',
      showBack: false,
      error: _error == null ? null : AuthError(message: _error!),
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KoloField(
                label: 'Phone number',
                controller: _identifier,
                hint: '803 412 7788',
                keyboard: TextInputType.phone,
                action: TextInputAction.next,
                height: 56,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                autofillHints: const [AutofillHints.telephoneNumber],
                prefix: Padding(
                  padding: const EdgeInsets.only(left: 15, right: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '+234',
                        style: TextStyle(
                          fontFamily: KoloType.family,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: c.textSoft,
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 24,
                        margin: const EdgeInsets.only(left: 10),
                        color: c.hairline,
                      ),
                    ],
                  ),
                ),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'Enter your phone number' : null,
                onSubmitted: () => _passwordFocus.requestFocus(),
              ),
              KoloField(
                label: 'Passcode',
                controller: _password,
                hint: 'Your passcode',
                obscure: _obscure,
                action: TextInputAction.done,
                height: 56,
                fontSize: 17,
                autofillHints: const [AutofillHints.password],
                validator: (value) =>
                    (value == null || value.isEmpty) ? 'Enter your passcode' : null,
                onSubmitted: _submit,
                suffix: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    size: 18,
                  ),
                  color: c.textFaint,
                  tooltip: _obscure ? 'Show passcode' : 'Hide passcode',
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _RememberBox(
                    checked: _remember,
                    onTap: () => setState(() => _remember = !_remember),
                  ),
                  const SizedBox(width: 9),
                  Text(
                    'Remember this phone',
                    style: TextStyle(
                      fontFamily: KoloType.family,
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: c.text,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _busy
                        ? null
                        : () => koloToast(
                              context,
                              'Passcode reset is handled by your group admin for now.',
                            ),
                    child: Text(
                      'Forgot passcode?',
                      style: TextStyle(
                        fontFamily: KoloType.family,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: c.accentText,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              KoloSubmitButton(
                label: 'Sign in',
                busyLabel: 'Signing in…',
                busy: _busy,
                onPressed: _submit,
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(child: Container(height: 1, color: c.hairline)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'or',
                style: TextStyle(
                  fontFamily: KoloType.family,
                  fontSize: 11.5,
                  color: c.textFaint,
                ),
              ),
            ),
            Expanded(child: Container(height: 1, color: c.hairline)),
          ],
        ),
        const SizedBox(height: 22),
        SizedBox(
          height: 54,
          child: OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () => koloToast(context, 'Fingerprint unlock is not wired in this build.'),
            icon: Icon(Icons.fingerprint_rounded, size: 20, color: c.text),
            label: Text(
              'Use fingerprint',
              style: TextStyle(
                fontFamily: KoloType.family,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.13,
                color: c.text,
              ),
            ),
            style: OutlinedButton.styleFrom(
              backgroundColor: c.surfaceRaised,
              side: BorderSide(color: c.hairline),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ],
      footer: Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Center(
          child: GestureDetector(
            onTap: _busy ? null : () => context.go('/register'),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'New to KOLO? ',
                    style: TextStyle(
                      fontFamily: KoloType.family,
                      fontSize: 13,
                      color: c.textSoft,
                    ),
                  ),
                  TextSpan(
                    text: 'Create an account',
                    style: TextStyle(
                      fontFamily: KoloType.family,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: c.accentText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The design's own checkbox: a 20 px ink square with a white tick, not
/// Material's ripple-on-tap box, which draws two nested shapes and reads as
/// a form control rather than a decision.
class _RememberBox extends StatelessWidget {
  const _RememberBox({required this.checked, required this.onTap});

  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      checked: checked,
      label: 'Remember this phone',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: checked ? c.text : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: checked ? c.text : c.textFaint, width: 1.5),
          ),
          child: checked
              ? Icon(Icons.check_rounded, size: 14, color: c.surfaceRaised)
              : null,
        ),
      ),
    );
  }
}

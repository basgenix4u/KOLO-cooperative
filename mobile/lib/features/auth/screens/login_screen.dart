import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../design/components.dart';
import '../../../design/tokens.dart';
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
      subtitle: 'Sign in to see your groups, contributions and payouts.',
      error: _error == null ? null : AuthError(message: _error!),
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KoloField(
                label: 'Email or phone',
                controller: _identifier,
                hint: 'you@example.com',
                keyboard: TextInputType.emailAddress,
                action: TextInputAction.next,
                autofillHints: const [AutofillHints.username, AutofillHints.email],
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'Enter your email or phone' : null,
                onSubmitted: () => _passwordFocus.requestFocus(),
              ),
              const SizedBox(height: KoloSpace.lg),
              KoloField(
                label: 'Password',
                controller: _password,
                hint: 'Your password',
                obscure: _obscure,
                action: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                validator: (value) =>
                    (value == null || value.isEmpty) ? 'Enter your password' : null,
                onSubmitted: _submit,
                suffix: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    size: 19,
                  ),
                  color: c.textSoft,
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                ),
              ),
              const SizedBox(height: KoloSpace.md),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _busy
                      ? null
                      : () => koloToast(
                            context,
                            'Password reset is handled by your group admin for now.',
                          ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: KoloSpace.sm,
                      vertical: KoloSpace.sm,
                    ),
                    minimumSize: const Size(0, 40),
                  ),
                  child: const Text('Forgot your password?'),
                ),
              ),
              const SizedBox(height: KoloSpace.lg),
              KoloSubmitButton(
                label: 'Sign in',
                busyLabel: 'Signing in…',
                busy: _busy,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ],
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 52,
            child: OutlinedButton(
              onPressed: _busy ? null : () => context.go('/register'),
              child: const Text('Create an account'),
            ),
          ),
          const SizedBox(height: KoloSpace.xl),
          const KoloNotice(
            message: 'Sandbox build — no real money moves.',
            tone: KoloNoticeTone.neutral,
          ),
        ],
      ),
    );
  }
}

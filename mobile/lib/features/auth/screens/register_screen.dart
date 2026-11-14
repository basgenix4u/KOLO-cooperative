import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../design/components.dart';
import '../../../design/tokens.dart';
import '../auth_controller.dart';
import 'auth_scaffold.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  FocusNode? _emailFocus;
  FocusNode? _passwordFocus;
  bool _obscure = true;
  bool _busy = false;
  bool _agreed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _emailFocus = FocusNode();
    _passwordFocus = FocusNode();
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _emailFocus?.dispose();
    _passwordFocus?.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreed) {
      setState(() => _error = 'Please confirm you understand how group money works.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(authControllerProvider).register(
            email: _email.text,
            password: _password.text,
            fullName: _name.text,
          );
      if (!mounted) return;
      context.go('/verify?email=${Uri.encodeComponent(_email.text.trim())}');
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendly(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendly(ApiException error) {
    switch (error.code) {
      case 'email_taken':
      case 'already_exists':
        return 'An account already uses that email. Try signing in instead.';
      case 'weak_password':
        return 'Choose a longer password — at least 8 characters.';
      case 'invalid_email':
        return 'That email address does not look right.';
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
      title: 'Create your account',
      subtitle: 'You will confirm your email before your first payment. '
          'An account that has not been verified cannot hold money.',
      error: _error == null ? null : AuthError(message: _error!),
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KoloField(
                label: 'Full name',
                controller: _name,
                hint: 'As it appears on your ID',
                textCapitalization: TextCapitalization.words,
                action: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                validator: (value) {
                  final v = value?.trim() ?? '';
                  if (v.isEmpty) return 'Enter your name';
                  if (v.length < 2) return 'That name looks too short';
                  if (!v.contains(' ')) return 'Include your surname';
                  return null;
                },
                onSubmitted: () => _emailFocus?.requestFocus(),
              ),
              const SizedBox(height: KoloSpace.lg),
              KoloField(
                label: 'Email',
                controller: _email,
                hint: 'you@example.com',
                keyboard: TextInputType.emailAddress,
                action: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                validator: (value) {
                  final v = value?.trim() ?? '';
                  if (v.isEmpty) return 'Enter your email';
                  // Deliberately loose: the verification email is the real
                  // check, and a clever regex only rejects valid addresses.
                  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)) {
                    return 'That does not look like an email address';
                  }
                  return null;
                },
                onSubmitted: () => _passwordFocus?.requestFocus(),
              ),
              const SizedBox(height: KoloSpace.lg),
              KoloField(
                label: 'Password',
                controller: _password,
                hint: 'At least 8 characters',
                obscure: _obscure,
                onChanged: (_) => setState(() {}),
                action: TextInputAction.done,
                autofillHints: const [AutofillHints.newPassword],
                validator: (value) {
                  final v = value ?? '';
                  if (v.isEmpty) return 'Choose a password';
                  if (v.length < 8) return 'Use at least 8 characters';
                  return null;
                },
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
              PasswordStrength(password: _password.text),
              const SizedBox(height: KoloSpace.lg),
              _Consent(
                value: _agreed,
                onChanged: (v) => setState(() {
                  _agreed = v;
                  if (v) _error = null;
                }),
              ),
              const SizedBox(height: KoloSpace.xl),
              KoloSubmitButton(
                label: 'Create my account',
                busyLabel: 'Creating your account…',
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
              onPressed: _busy ? null : () => context.go('/login'),
              child: const Text('I already have an account'),
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

/// Consent is a deliberate tap, not a pre-ticked box.
///
/// The two things stated here are the two that cost members money when they are
/// misunderstood: money is collected by the group, and payouts need agreement.
class _Consent extends StatelessWidget {
  const _Consent({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      checked: value,
      label: 'I understand contributions are collected by my group and payouts '
          'need everyone who must approve them',
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(KoloRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: KoloSpace.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: value,
                  onChanged: (v) => onChanged(v ?? false),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(width: KoloSpace.md),
              Expanded(
                child: Text(
                  'I understand that contributions are collected by my group, '
                  'and payouts need agreement from more than one person.',
                  style: context.text.bodySmall?.copyWith(color: c.textSoft, height: 1.45),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

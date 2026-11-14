import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../design/components.dart';
import '../../../design/navigation.dart';
import '../../../design/tokens.dart';
import '../../../design/typography.dart';

/// The shared frame for every signed-out screen.
///
/// Three rules hold these screens together:
///
///  1. The member always knows where they are. A back chevron when there is
///     somewhere to go back to, the mark when there is not.
///  2. The primary action sits in the thumb zone and stays reachable when the
///     keyboard is up, which is why it is pinned to the bottom of the scroll
///     view rather than flowing after the fields.
///  3. Every screen can overflow. On a short viewport with a keyboard open
///     there may be 260 logical pixels of usable height, so nothing here has a
///     fixed height and nothing is allowed to clip.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    this.footer,
    this.error,
    this.notice,
    this.showBack = true,
    this.onBack,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;
  final Widget? footer;
  final Widget? error;
  final Widget? notice;
  final bool showBack;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.surface,
      // Resizes so the pinned action rides above the keyboard instead of being
      // hidden behind it.
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                KoloSpace.page, KoloSpace.sm, KoloSpace.page, 0),
              child: Row(
                children: [
                  if (showBack)
                    KoloBackButton(
                      onTap: onBack ?? () => context.canPop() ? context.pop() : context.go('/welcome'),
                    )
                  else
                    const SizedBox(height: 44),
                  const Spacer(),
                  const KoloMark(size: 22),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  KoloSpace.page,
                  KoloSpace.xl,
                  KoloSpace.page,
                  // Clear the home indicator plus a little breathing room.
                  KoloSpace.page + MediaQuery.paddingOf(context).bottom,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: KoloSpace.maxContent),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.displaySmall,
                        ),
                        const SizedBox(height: KoloSpace.sm + 2),
                        Text(
                          subtitle,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: c.textSoft, height: 1.5),
                        ),
                        if (notice != null) ...[
                          const SizedBox(height: KoloSpace.lg),
                          notice!,
                        ],
                        if (error != null) ...[
                          const SizedBox(height: KoloSpace.lg),
                          error!,
                        ],
                        const SizedBox(height: KoloSpace.xl + 4),
                        ...children,
                        if (footer != null) ...[
                          const SizedBox(height: KoloSpace.xxl),
                          footer!,
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A labelled field with the app's own label instead of Material's floating
/// label. Floating labels slide over the value as it is typed, which is the
/// opposite of what someone entering a password wants to look at.
class KoloField extends StatelessWidget {
  const KoloField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.helper,
    this.obscure = false,
    this.keyboard,
    this.action = TextInputAction.next,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.suffix,
    this.prefix,
    this.autofillHints,
    this.enabled = true,
    this.maxLines = 1,
    this.textCapitalization = TextCapitalization.none,
    this.autofocus = false,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final String? helper;
  final bool obscure;
  final TextInputType? keyboard;
  final TextInputAction action;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSubmitted;
  final Widget? suffix;
  final Widget? prefix;
  final Iterable<String>? autofillHints;
  final bool enabled;
  final int maxLines;
  final TextCapitalization textCapitalization;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: KoloType.eyebrow(c).copyWith(color: c.textSoft),
        ),
        const SizedBox(height: KoloSpace.sm),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboard,
          textInputAction: action,
          textCapitalization: textCapitalization,
          validator: validator,
          onChanged: onChanged,
          onFieldSubmitted: (_) => onSubmitted?.call(),
          autofillHints: autofillHints,
          enabled: enabled,
          maxLines: maxLines,
          autofocus: autofocus,
          style: TextStyle(
            fontFamily: KoloType.family,
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: enabled ? c.text : c.textFaint,
          ),
          decoration: InputDecoration(
            hintText: hint,
            helperText: helper,
            helperMaxLines: 2,
            prefixIcon: prefix,
            suffixIcon: suffix,
            // A tall field is a finger-friendly field. Material's default is
            // 48dp; 56 gives a comfortable target without looking inflated.
            contentPadding: const EdgeInsets.symmetric(
              horizontal: KoloSpace.lg,
              vertical: KoloSpace.lg + 2,
            ),
          ),
        ),
      ],
    );
  }
}

/// Error text that reads as a sentence, not a code.
class AuthError extends StatelessWidget {
  const AuthError({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return KoloNotice(
      message: message,
      tone: KoloNoticeTone.critical,
      icon: Icons.error_outline_rounded,
    );
  }
}

/// Password strength as words first, colour second.
///
/// A bar alone tells the member nothing they can act on. The words say what to
/// change; the colour and the bar reinforce it for anyone scanning.
class PasswordStrength extends StatelessWidget {
  const PasswordStrength({super.key, required this.password});

  final String password;

  /// Eight is the backend's floor. Length beyond that is worth more than
  /// symbol-counting, so variety is a bonus rather than a gate.
  static int score(String value) {
    if (value.isEmpty) return 0;
    if (value.length < 8) return 1;
    var s = 2;
    final hasLetter = RegExp(r'[A-Za-z]').hasMatch(value);
    final hasDigit = RegExp(r'\d').hasMatch(value);
    final hasOther = RegExp(r'[^A-Za-z0-9]').hasMatch(value);
    if (hasLetter && hasDigit) s = 3;
    if (hasLetter && hasDigit && hasOther) s = 4;
    if (value.length >= 14 && s < 4) s = 4;
    return s;
  }

  static const _labels = ['', 'Too short', 'Weak', 'Good', 'Strong'];
  static const _advice = [
    '',
    'At least 8 characters.',
    'Add a number, or make it longer.',
    'Add a symbol to make it stronger.',
    'That will do nicely.',
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (password.isEmpty) return const SizedBox.shrink();
    final level = score(password);
    final tone = switch (level) {
      1 => c.failed,
      2 => c.pending,
      3 => c.accentText,
      _ => c.settled,
    };
    return Semantics(
      liveRegion: true,
      label: 'Password strength: ${_labels[level]}. ${_advice[level]}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 1; i <= 4; i++) ...[
                Expanded(
                  child: AnimatedContainer(
                    duration: KoloMotion.fast,
                    height: 3,
                    decoration: BoxDecoration(
                      color: i <= level ? tone : c.hairline,
                      borderRadius: BorderRadius.circular(KoloRadius.full),
                    ),
                  ),
                ),
                if (i < 4) const SizedBox(width: 4),
              ],
            ],
          ),
          const SizedBox(height: KoloSpace.sm),
          Text(
            _advice[level],
            style: context.text.bodySmall?.copyWith(color: c.textSoft),
          ),
        ],
      ),
    );
  }
}

/// A keyboard-aware wrapper for short numeric codes.
///
/// One field rather than six boxes: six boxes fight the platform's paste, its
/// autofill and its accessibility tree, and members routinely type a code from
/// a notification without leaving the app.
class CodeField extends StatelessWidget {
  const CodeField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.onComplete,
    this.length = 6,
    this.enabled = true,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onComplete;
  final int length;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.oneTimeCode],
      maxLength: length,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: (value) {
        onChanged(value);
        if (value.length == length) onComplete?.call(value);
      },
      style: TextStyle(
        fontFamily: KoloType.family,
        fontSize: 30,
        fontWeight: FontWeight.w700,
        letterSpacing: 10,
        color: c.text,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      textAlign: TextAlign.center,
      decoration: InputDecoration(
        counterText: '',
        hintText: '•' * length,
        hintStyle: TextStyle(
          fontFamily: KoloType.family,
          fontSize: 30,
          letterSpacing: 10,
          color: c.textFaint,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: KoloSpace.lg,
          vertical: KoloSpace.lg + 4,
        ),
      ),
    );
  }
}

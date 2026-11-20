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
      backgroundColor: c.ground,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const KoloStatusBar(),
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  KoloSpace.page,
                  10,
                  KoloSpace.page,
                  24 + MediaQuery.paddingOf(context).bottom,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: KoloSpace.maxContent),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            if (showBack)
                              KoloBackButton(
                                onTap: onBack ??
                                    () => context.canPop()
                                        ? context.pop()
                                        : context.go('/welcome'),
                              )
                            else
                              const _Wordmark(),
                            const Spacer(),
                          ],
                        ),
                        const SizedBox(height: 30),
                        Text(
                          title,
                          style: TextStyle(
                            fontFamily: KoloType.family,
                            fontSize: 28,
                            height: 1.15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.7,
                            color: c.text,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontFamily: KoloType.family,
                            fontSize: 13,
                            height: 1.45,
                            fontWeight: FontWeight.w400,
                            color: c.textSoft,
                          ),
                        ),
                        const SizedBox(height: 26),
                        if (notice != null) ...[
                          notice!,
                          const SizedBox(height: 18),
                        ],
                        if (error != null) ...[
                          error!,
                          const SizedBox(height: 18),
                        ],
                        ...children,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (footer != null) footer!,
          ],
        ),
      ),
    );
  }
}

/// The mark and wordmark, as the design draws it at the top of a signed-out
/// screen. The tracking is the identity: KOLO at 0.16em is a logo.
class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        KoloMark(size: 15, color: c.text, semanticLabel: 'KOLO'),
        const SizedBox(width: 10),
        Text(
          'KOLO',
          style: TextStyle(
            fontFamily: KoloType.family,
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.4,
            color: c.text,
          ),
        ),
      ],
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
    this.height = 56,
    this.fontSize = 15,
    this.fontWeight = FontWeight.w500,
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
  final double height;
  final double fontSize;
  final FontWeight fontWeight;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(KoloRadius.md);

    OutlineInputBorder border(Color colour, double width) => OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: colour, width: width),
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: KoloType.family,
              fontSize: 12.5,
              height: 1.45,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.06,
              color: c.textSoft,
            ),
          ),
          const SizedBox(height: 7),
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
            cursorColor: c.accentText,
            style: TextStyle(
              fontFamily: KoloType.family,
              fontSize: fontSize,
              fontWeight: fontWeight,
              color: enabled ? c.text : c.textFaint,
            ),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: c.surfaceRaised,
              hintText: hint,
              hintStyle: TextStyle(
                fontFamily: KoloType.family,
                fontSize: fontSize,
                fontWeight: FontWeight.w400,
                color: c.textFaint,
              ),
              helperText: helper,
              helperMaxLines: 2,
              helperStyle: TextStyle(
                fontFamily: KoloType.family,
                fontSize: 11.5,
                height: 1.45,
                color: c.textFaint,
              ),
              prefixIcon: prefix,
              suffixIcon: suffix,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 15,
                vertical: height / 2 - fontSize * 0.72,
              ),
              constraints: BoxConstraints(minHeight: height),
              floatingLabelBehavior: FloatingLabelBehavior.never,
              border: border(c.hairline, 1.5),
              enabledBorder: border(c.hairline, 1.5),
              focusedBorder: border(c.accentText, 1.5),
              errorBorder: border(c.failed, 1.5),
              focusedErrorBorder: border(c.failed, 1.5),
              errorStyle: TextStyle(
                fontFamily: KoloType.family,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: c.failed,
              ),
            ),
          ),
        ],
      ),
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

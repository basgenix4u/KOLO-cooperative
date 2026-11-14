import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design/navigation.dart';
import '../../../design/tokens.dart';
import '../../../design/typography.dart';
import '../../../core/theme/theme_mode.dart';

/// The first screen a new member sees.
///
/// One idea, stated plainly: cooperative savings, but with the arithmetic done
/// properly. No carousel, no three-step walkthrough, no stock illustration of
/// people holding hands — the onboarding asks for one decision (who are you
/// here as) and gets out of the way.
///
/// The Midnight Ink field is the brand's authority. Citrus appears exactly once,
/// on the primary action, so the eye has one place to land.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      backgroundColor: KoloBrand.ink,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Below this height the composition condenses: the three proof
            // points collapse to one line each and the display type steps down.
            final compact = constraints.maxHeight < 700;
            return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    KoloSpace.page, KoloSpace.xl, KoloSpace.page, KoloSpace.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: const [KoloMark(size: 26)],
                      ),

                      // Gap sizes follow the available height rather than using
                      // Spacer: on a short screen the spacing tightens instead of
                      // the actions being pushed off the bottom.
                      SizedBox(height: compact ? KoloSpace.section : 72.0),

                      // The claim. Set large, tight and in two beats so it can
                      // be read at a glance rather than parsed as a paragraph.
                      Text(
                        'Saved together.',
                        style: _display(context, compact),
                      ),
                      Text(
                        'Counted properly.',
                        style: _display(context, compact).copyWith(color: KoloBrand.citrus),
                      ),

                      const SizedBox(height: KoloSpace.lg),

                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 340),
                        child: Text(
                          'Ajo, esusu and adashe have always worked because people trust '
                          'each other. KOLO keeps that trust and does the bookkeeping: every '
                          'contribution recorded, every payout approved by two people, every '
                          'naira accounted for.',
                          style: TextStyle(
                            fontFamily: KoloType.family,
                            fontSize: 14.5,
                            height: 1.6,
                            color: Colors.white.withValues(alpha: 0.66),
                          ),
                        ),
                      ),

                      SizedBox(height: compact ? KoloSpace.xl : 40.0),

                      SizedBox(height: compact ? KoloSpace.lg : KoloSpace.xl),

                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => context.push('/register'),
                          style: FilledButton.styleFrom(
                            backgroundColor: KoloBrand.citrus,
                            foregroundColor: KoloBrand.ink,
                            minimumSize: const Size.fromHeight(54),
                          ),
                          child: const Text('Create your account'),
                        ),
                      ),
                      const SizedBox(height: KoloSpace.md),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () => context.push('/login'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(54),
                            side: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
                          ),
                          child: const Text('I already have an account'),
                        ),
                      ),

                      const SizedBox(height: KoloSpace.md),

                      // Three facts, not three features. Each is something the
                      // product genuinely does today.
                      const _ProofRow(
                        icon: Icons.receipt_long_rounded,
                        text: 'Every contribution gets a reference you can check',
                      ),
                      const _ProofRow(
                        icon: Icons.verified_user_rounded,
                        text: 'Payouts need one officer to request, another to approve',
                      ),
                      const _ProofRow(
                        icon: Icons.groups_rounded,
                        text: 'Built for ajo, esusu and adashe as they are actually run',
                      ),

                      // Honesty about the environment, above the fold, before a
                      // member puts anything in. This is not a legal footnote.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 13,
                            color: Colors.white.withValues(alpha: 0.45),
                          ),
                          const SizedBox(width: KoloSpace.sm),
                          Expanded(
                            child: Text(
                              'Sandbox build — no real money moves.',
                              style: TextStyle(
                                fontFamily: KoloType.family,
                                fontSize: 11.5,
                                height: 1.4,
                                color: Colors.white.withValues(alpha: 0.45),
                              ),
                            ),
                          ),
                        ],
                      ),

                      Center(
                        child: TextButton.icon(
                          onPressed: () => _cycleTheme(context, ref, themeMode),
                          icon: Icon(
                            _themeIcon(themeMode),
                            size: 15,
                            color: Colors.white.withValues(alpha: 0.55),
                          ),
                          label: Text(
                            themeModeNextLabel(themeMode),
                            style: TextStyle(
                              fontFamily: KoloType.family,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.55),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// The welcome screen is deliberately always ink, so the appearance toggle
  /// here sets the *signed-in* appearance rather than changing this screen.
  static Future<void> _cycleTheme(
    BuildContext context,
    WidgetRef ref,
    ThemeMode current,
  ) async {
    final next = switch (current) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    await ref.read(themeModeProvider.notifier).set(next);
  }

  static IconData _themeIcon(ThemeMode mode) => switch (mode) {
        ThemeMode.system => Icons.brightness_auto_rounded,
        ThemeMode.light => Icons.light_mode_rounded,
        ThemeMode.dark => Icons.dark_mode_rounded,
      };

  static TextStyle _display(BuildContext context, bool compact) => TextStyle(
        fontFamily: KoloType.family,
        fontSize: compact ? 32 : 40,
        height: 1.08,
        letterSpacing: -1.4,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      );
}

class _ProofRow extends StatelessWidget {
  const _ProofRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: KoloSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(KoloRadius.sm),
            ),
            child: Icon(icon, size: 15, color: KoloBrand.citrus),
          ),
          const SizedBox(width: KoloSpace.md),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                text,
                style: TextStyle(
                  fontFamily: KoloType.family,
                  fontSize: 13.5,
                  height: 1.45,
                  color: Colors.white.withValues(alpha: 0.80),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

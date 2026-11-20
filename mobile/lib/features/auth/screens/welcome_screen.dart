import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../design/navigation.dart';
import '../../../design/tokens.dart';
import '../../../design/typography.dart';

/// The first screen a new member sees.
///
/// One idea, stated plainly: cooperative savings, but with the arithmetic done
/// properly. No carousel, no three-step walkthrough, no stock illustration of
/// people holding hands — the onboarding asks for one decision and gets out of
/// the way.
///
/// The Midnight Ink field is the brand's authority. Citrus appears exactly
/// twice: the trust pill and the primary action, so the eye has one place to
/// land and one reassurance to read before it gets there.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KoloBrand.ink,
      body: Stack(
        children: [
          Positioned.fill(
            child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const KoloStatusBar(dark: true),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // The reference composition is tuned for a 770 px content area
                // (844 minus the status band and the bottom inset). Below that
                // the same column simply scrolls rather than being squeezed.
                final scrolls = constraints.maxHeight < 620;
                if (scrolls) {
                  return SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 26),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const _BrandRow(),
                          const SizedBox(height: 28),
                          const _Content(),
                        ],
                      ),
                    ),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 26),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _BrandRow(),
                      const Spacer(),
                      const _Content(),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
            ),
          ),
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 134,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Everything below the wordmark: pill, claim, explanation, three proofs, the
/// two actions, and the sandbox line.
class _Content extends StatelessWidget {
  const _Content();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 21),
        const _TrustPill(),
        const SizedBox(height: 20),
        const _Headline(),
        const SizedBox(height: 20),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 285),
          child: Text(
            'Ajo, esusu and adashe already work\n'
            'because people trust each other. KOLO\n'
            'is the book that keeps that trust —\n'
            'every contribution, every payout, and a\n'
            'second signature before any money leaves.',
            style: TextStyle(
              fontFamily: KoloType.family,
              fontSize: 14,
              height: 1.6,
              fontWeight: FontWeight.w400,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
        ),
        const SizedBox(height: 28),
        const _ProofPoint(
          icon: Icons.receipt_long_rounded,
          text: 'Every payment gets a receipt you can show anyone',
        ),
        const SizedBox(height: 9),
        const _ProofPoint(
          icon: Icons.shield_outlined,
          text: 'No officer can pay out alone',
        ),
        const SizedBox(height: 9),
        const _ProofPoint(
          icon: Icons.groups_outlined,
          text: 'Built for groups of 8 to 200',
        ),
        const SizedBox(height: 26),
        _PillButton(
          label: 'Get started',
          primary: true,
          onTap: () => context.go('/register'),
        ),
        const SizedBox(height: 10),
        _PillButton(
          label: 'I already have an account',
          primary: false,
          onTap: () => context.go('/login'),
        ),
        const SizedBox(height: 16),
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.35),
                ),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  'Sandbox build — no real money moves',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: KoloType.family,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w400,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The mark and the wordmark, with the language selector opposite.
///
/// The wordmark is tracked out to 0.16em: at this size KOLO is a logo, not a
/// word, and the spacing is what makes it read as one.
class _BrandRow extends StatelessWidget {
  const _BrandRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          const KoloMark(size: 20, color: KoloBrand.citrus, semanticLabel: 'KOLO'),
          const SizedBox(width: 9),
          Text(
            'KOLO',
            style: TextStyle(
              fontFamily: KoloType.family,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 2.4,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.language_rounded,
                    size: 13, color: Colors.white.withValues(alpha: 0.75)),
                const SizedBox(width: 5),
                Text(
                  'EN',
                  style: TextStyle(
                    fontFamily: KoloType.family,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrustPill extends StatelessWidget {
  const _TrustPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: KoloBrand.citrus.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.shield_outlined, size: 13, color: KoloBrand.citrus),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'TWO SIGNATURES, EVERY PAYOUT',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: KoloType.family,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: KoloBrand.citrus,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline();

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontFamily: KoloType.family,
      fontSize: 40,
      height: 1.03,
      fontWeight: FontWeight.w800,
      letterSpacing: -1.52,
      color: Colors.white,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Saved\ntogether.', style: base),
        Text('Counted\nproperly.', style: base.copyWith(color: KoloBrand.citrus)),
      ],
    );
  }
}

class _ProofPoint extends StatelessWidget {
  const _ProofPoint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: KoloBrand.citrus.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: KoloBrand.citrus),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontFamily: KoloType.family,
              fontSize: 12.5,
              height: 1.4,
              fontWeight: FontWeight.w400,
              color: Colors.white.withValues(alpha: 0.72),
            ),
          ),
        ),
      ],
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.primary,
    required this.onTap,
  });

  final String label;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 54,
          width: double.infinity,
          decoration: BoxDecoration(
            color: primary ? KoloBrand.citrus : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            boxShadow: primary
                ? [
                    BoxShadow(
                      color: KoloBrand.citrusDeep.withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontFamily: KoloType.family,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.13,
              color: primary ? KoloBrand.ink : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeIndicator extends StatelessWidget {
  const _HomeIndicator();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 9, bottom: 0),
      child: Center(
        child: Container(
          width: 134,
          height: 5,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../design/typography.dart';
import '../core/models/money.dart';

/// ============================================================================
/// KOLO component library.
///
/// Every screen is assembled from these. Screens lay out; these decide how a
/// thing looks, how it responds to touch, and what it says when it has nothing
/// to show. If a screen needs a new visual idea, it is added here first, so the
/// product keeps one vocabulary.
/// ============================================================================

/// The panel everything sits on.
///
/// Square-ish corners (16), a hairline border and no shadow. Depth in this
/// product comes from the ink/stone contrast, not from dropshadows, which read
/// as decoration on a phone.
class KoloCard extends StatelessWidget {
  const KoloCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.color,
    this.border,
    this.radius,
    this.elevated = false,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? border;
  final double? radius;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = radius ?? KoloRadius.lg;
    final bg = color ?? (elevated ? c.surfaceRaised : c.surface);

    final body = Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(KoloSpace.lg),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(r),
        border: Border.all(color: border ?? c.hairline, width: 1),
      ),
      child: child,
    );

    if (onTap == null) return body;

    // The ripple is clipped to the card so the touch feedback respects the
    // corner radius instead of bleeding into a square.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(r),
        splashColor: c.accentWash,
        highlightColor: c.accentWash,
        child: body,
      ),
    );
  }
}

/// The one number a screen is about.
///
/// A hero figure is set large, tabular, with the currency mark reduced so the
/// quantity dominates. `FittedBox` scales it down rather than overflowing —
/// a ₦12,450,000.00 balance on a 320dp phone must still be fully readable,
/// never clipped and never ellipsised, because a truncated balance is a wrong
/// balance.
class KoloAmount extends StatelessWidget {
  const KoloAmount({
    super.key,
    required this.money,
    this.size = 40,
    this.color,
    this.weight = FontWeight.w700,
    this.showCurrency = true,
    this.semanticLabel,
  });

  final Money money;
  final double size;
  final Color? color;
  final FontWeight weight;
  final bool showCurrency;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = color ?? c.text;
    final symbol = Money.symbolFor(money.currency);
    // Grouping only; the decimals are dropped from the hero figure because at
    // 40px the kobo are noise. The exact figure is always available in the
    // spoken label and on the detail rows.
    final whole = money.format(withSymbol: false).split('.').first;

    return Semantics(
      label: semanticLabel ??
          '${money.format(withSymbol: false)} ${money.currency}',
      excludeSemantics: true,
      // `scaleDown`, never up. A balance is set at a commanding size and only
      // shrinks when the digits genuinely will not fit (a nine-figure balance on
      // a 320dp phone). Scaling up turns a small number into an absurd one and
      // destroys the typographic hierarchy the hero figure depends on.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          // One baseline for all three parts. The currency mark and the kobo are
          // smaller, not higher: they sit on the same line as the figures they
          // belong to, which is what makes the group read as one number.
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showCurrency)
              Text(
                symbol,
                style: KoloType.currencyMark(
                  c,
                  size: size,
                  color: tone.withValues(alpha: 0.72),
                ),
              ),
            if (showCurrency) SizedBox(width: size * 0.09),
            Text(whole, style: KoloType.money(c, size: size, weight: weight, color: tone)),
            if (money.decimalPlaces > 0)
              Text(
                '.${(money.minor.abs() % 100).toString().padLeft(2, '0')}',
                style: KoloType.money(
                  c,
                  size: size * 0.45,
                  weight: FontWeight.w600,
                  color: tone.withValues(alpha: 0.5),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A quieter amount for rows and secondary figures.
class KoloAmountSmall extends StatelessWidget {
  const KoloAmountSmall({
    super.key,
    required this.money,
    this.size = 15,
    this.color,
    this.weight = FontWeight.w600,
    this.signed = false,
  });

  final Money money;
  final double size;
  final Color? color;
  final FontWeight weight;
  /// Prefix a + or − for movements.
  final bool signed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sign = signed ? (money.isNegative ? '−' : '+') : (money.isNegative ? '−' : '');
    final text = '${sign}${Money.symbolFor(money.currency)}${money.abs.format(withSymbol: false)}';
    return Text(
      text,
      style: KoloType.money(c, size: size, weight: weight, color: color ?? c.text),
      maxLines: 1,
      softWrap: false,
    );
  }
}

/// Status is never carried by colour alone.
///
/// Every pill has a glyph *and* a word, so a member with a red/green colour
/// deficiency — or a greyscale screenshot — reads exactly the same status.
class KoloStatusPill extends StatelessWidget {
  const KoloStatusPill({super.key, required this.status, this.label, this.compact = false});

  final String status;
  final String? label;
  final bool compact;

  /// Resolves a server status string to the words and glyph it will be shown
  /// with. Public because this mapping is what stops a member having to read
  /// colour alone, so it is worth testing directly.
  static KoloStatusSpec resolve(String status) {
    final tone = _toneFor(status);
    return KoloStatusSpec(
      label: _humanise(status),
      glyph: _glyphFor(tone),
      tone: tone,
    );
  }

  _StatusTone get _tone => _toneFor(status);

  static _StatusTone _toneFor(String status) {
    const settled = {
      'active', 'confirmed', 'settled', 'paid', 'succeeded', 'passed', 'approved',
      'completed', 'verified',
    };
    const pending = {
      'pending', 'pending_approval', 'awaiting_payment', 'collecting', 'processing',
      'scheduled', 'submitted', 'open', 'in_review', 'requested', 'initiated',
    };
    const failed = {
      'overdue', 'failed', 'rejected', 'cancelled', 'shortfall', 'defaulted',
      'blocked', 'declined', 'expired',
    };
    const highlighted = {'ready_for_payout', 'payout_pending_approval', 'disbursed'};
    if (settled.contains(status)) return _StatusTone.settled;
    if (pending.contains(status)) return _StatusTone.pending;
    if (failed.contains(status)) return _StatusTone.failed;
    if (highlighted.contains(status)) return _StatusTone.highlighted;
    return _StatusTone.neutral;
  }

  IconData get _icon => _glyphFor(_tone);

  static IconData _glyphFor(_StatusTone tone) => switch (tone) {
        _StatusTone.settled => Icons.check_circle_rounded,
        _StatusTone.pending => Icons.schedule_rounded,
        _StatusTone.failed => Icons.error_rounded,
        _StatusTone.highlighted => Icons.bolt_rounded,
        _StatusTone.neutral => Icons.circle_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (bg, fg) = switch (_tone) {
      _StatusTone.settled => (c.settledWash, c.settled),
      _StatusTone.pending => (c.pendingWash, c.pending),
      _StatusTone.failed => (c.failedWash, c.failed),
      _StatusTone.highlighted => (c.accentWash, c.accentText),
      _StatusTone.neutral => (c.surfaceSunken, c.textSoft),
    };
    final text = label ?? _humanise(status);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? KoloSpace.sm : KoloSpace.md,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(KoloRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon, size: compact ? 10 : 12, color: fg),
          SizedBox(width: compact ? 3 : 5),
          Text(
            text,
            style: TextStyle(
              fontFamily: KoloType.family,
              fontSize: compact ? 10.5 : 12,
              fontWeight: FontWeight.w600,
              color: fg,
              height: 1.2,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

enum _StatusTone { settled, pending, failed, highlighted, neutral }

/// What a status will be rendered as: a word, a glyph and a tone.
///
/// Every status must resolve to all three. Colour is the last of them, because a
/// member with a colour-vision deficiency reads the word and the shape first.
class KoloStatusSpec {
  const KoloStatusSpec({
    required this.label,
    required this.glyph,
    required this.tone,
  });

  final String label;
  final IconData glyph;
  final Object tone;
}

String _humanise(String raw) {
  if (raw.isEmpty) return '';
  final words = raw.replaceAll('_', ' ').trim();
  return words[0].toUpperCase() + words.substring(1);
}

/// Section heading: an eyebrow, a title and an optional action.
///
/// This is the app's only section header. Repeating it everywhere is what makes
/// a long screen scannable instead of a wall of cards.
class KoloSectionHeader extends StatelessWidget {
  const KoloSectionHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.action,
    this.padding,
    this.inset = true,
  });

  final String title;
  final String? eyebrow;
  final Widget? action;
  final EdgeInsetsGeometry? padding;

  /// Whether the header supplies its own page gutters. Set false when it is
  /// already inside padding, or the content ends up double-indented.
  final bool inset;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: padding ??
          EdgeInsets.only(
            left: inset ? KoloSpace.page : 0,
            right: inset ? KoloSpace.page : 0,
            top: inset ? KoloSpace.section : 0,
            bottom: KoloSpace.md,
          ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null) ...[
                  Text(eyebrow!.toUpperCase(), style: KoloType.eyebrow(c)),
                  const SizedBox(height: KoloSpace.xs + 2),
                ],
                Text(title, style: context.text.titleLarge),
              ],
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

/// A single line of financial activity: what happened, when, and how much.
class KoloActivityRow extends StatelessWidget {
  const KoloActivityRow({
    super.key,
    required this.title,
    required this.amount,
    this.subtitle,
    this.status,
    this.icon,
    this.onTap,
    this.amountColor,
    this.showDivider = true,
  });

  final String title;
  final Money amount;
  final String? subtitle;
  final String? status;
  final IconData? icon;
  final VoidCallback? onTap;
  final Color? amountColor;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    // A ledger row, not a list row: what it was and its identifier on the left,
    // the amount and its state on the right. Squeezing a status pill, a date and
    // a reference into one 12px line truncated all three and made a payment
    // reference — the one thing an officer searches for — unreadable.
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: KoloSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: c.surfaceSunken,
              borderRadius: BorderRadius.circular(KoloRadius.sm + 2),
            ),
            child: Icon(icon ?? Icons.swap_horiz_rounded, size: 17, color: c.textSoft),
          ),
          const SizedBox(width: KoloSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: context.text.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: context.text.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: KoloSpace.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              KoloAmountSmall(money: amount, color: amountColor),
              if (status != null) ...[
                const SizedBox(height: 4),
                KoloStatusPill(status: status!, compact: true),
              ],
            ],
          ),
        ],
      ),
    );

    final content = showDivider
        ? Column(children: [row, Divider(color: c.hairline, height: 1)])
        : row;

    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(KoloRadius.sm),
      child: content,
    );
  }
}

class KoloProgress extends StatelessWidget {
  const KoloProgress({
    super.key,
    required this.value,
    this.height = 6,
    this.color,
    this.track,
    this.semanticLabel,
  });

  /// 0..1, clamped — a server-reported percentage over 100 must not paint
  /// outside the track.
  final double value;
  final double height;
  final Color? color;
  final Color? track;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return Semantics(
      label: semanticLabel,
      value: '${(v * 100).round()} percent',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            children: [
              Container(
                height: height,
                width: constraints.maxWidth,
                color: track ?? c.hairline,
              ),
              TweenAnimationBuilder(
                tween: Tween<double>(begin: 0, end: v),
                duration: const Duration(seconds: 1),
                builder: (context, double animated, __) => Container(
                  height: height,
                  width: constraints.maxWidth * animated,
                  decoration: BoxDecoration(
                    color: color ?? c.text,
                    borderRadius: BorderRadius.circular(height),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Empty states teach; they do not just hold space.
///
/// Every empty state in this app names what will appear here, why it is empty,
/// and gives the one action that fills it.
class KoloEmptyState extends StatelessWidget {
  const KoloEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.inbox_rounded,
    this.action,
    this.illustration,
  });

  final String title;
  final String message;
  final IconData icon;
  final Widget? action;
  final Widget? illustration;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: KoloSpace.section,
          vertical: KoloSpace.hero,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            illustration ??
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: c.surfaceSunken,
                    borderRadius: BorderRadius.circular(KoloRadius.lg),
                  ),
                  child: Icon(icon, size: 28, color: c.textFaint),
                ),
            const SizedBox(height: KoloSpace.lg),
            Text(
              title,
              style: context.text.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: KoloSpace.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Text(
                message,
                style: context.text.bodyMedium?.copyWith(color: c.textSoft),
                textAlign: TextAlign.center,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: KoloSpace.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Loading placeholder that mirrors the shape of the content it replaces.
///
/// A skeleton is better than a spinner because it tells the member what is
/// about to arrive and stops the layout jumping when it does.
class KoloSkeleton extends StatefulWidget {
  const KoloSkeleton({
    super.key,
    this.width,
    this.height = 14,
    this.radius = 6,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  State<KoloSkeleton> createState() => _KoloSkeletonState();
}

class _KoloSkeletonState extends State<KoloSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (context.reduceMotion) {
      return _block(c.surfaceSunken);
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, __) {
        final t = Curves.easeInOut.transform(_controller.value);
        return _block(Color.lerp(c.surfaceSunken, c.surfaceRaised, t * 0.6)!);
      },
    );
  }

  Widget _block(Color color) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      );
}

/// A card-shaped skeleton for list loading.
class KoloSkeletonCard extends StatelessWidget {
  const KoloSkeletonCard({super.key, this.lines = 2, this.height});

  final int lines;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return KoloCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const KoloSkeleton(width: 120, height: 12),
          const SizedBox(height: KoloSpace.md),
          const KoloSkeleton(width: 200, height: 22),
          for (var i = 1; i < lines; i++) ...[
            const SizedBox(height: KoloSpace.sm),
            KoloSkeleton(width: 90.0 + (i * 40), height: 12),
          ],
        ],
      ),
    );
  }
}

/// Failure state.
///
/// Distinguishes "we cannot reach the server" from "the server refused", because
/// the member's next action differs: one is retry, the other is fix something.
class KoloErrorState extends StatelessWidget {
  const KoloErrorState({
    super.key,
    required this.message,
    this.title = 'Something went wrong',
    this.onRetry,
    this.isOffline = false,
  });

  final String message;
  final String title;
  final VoidCallback? onRetry;
  final bool isOffline;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: KoloSpace.section,
          vertical: KoloSpace.hero,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: isOffline ? c.pendingWash : c.failedWash,
                borderRadius: BorderRadius.circular(KoloRadius.lg),
              ),
              child: Icon(
                isOffline ? Icons.cloud_off_rounded : Icons.error_outline_rounded,
                size: 26,
                color: isOffline ? c.pending : c.failed,
              ),
            ),
            const SizedBox(height: KoloSpace.lg),
            Text(title, style: context.text.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: KoloSpace.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                message,
                style: context.text.bodyMedium?.copyWith(color: c.textSoft),
                textAlign: TextAlign.center,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: KoloSpace.xl),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A primary action that reports its own progress.
///
/// The button is the thing that was tapped, so the button is where the busy
/// state belongs. A spinner elsewhere on screen makes the member wonder whether
/// the tap registered.
class KoloSubmitButton extends StatelessWidget {
  const KoloSubmitButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.busyLabel,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final String? busyLabel;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: 54,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(c.accentText),
                ),
              )
            else if (icon != null)
              Icon(icon, size: 18),
            if (busy || icon != null) const SizedBox(width: KoloSpace.sm + 2),
            Flexible(
              child: Text(
                busy ? (busyLabel ?? label) : label,
                textAlign: TextAlign.center,
                maxLines: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An inline information strip: used for cached data, sandbox warnings, and
/// any place the app must be honest about a limitation.
class KoloNotice extends StatelessWidget {
  const KoloNotice({
    super.key,
    required this.message,
    this.icon = Icons.info_outline_rounded,
    this.tone = KoloNoticeTone.neutral,
    this.action,
  });

  final String message;
  final IconData icon;
  final KoloNoticeTone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (bg, fg) = switch (tone) {
      KoloNoticeTone.neutral => (c.surfaceSunken, c.textSoft),
      KoloNoticeTone.positive => (c.settledWash, c.settled),
      KoloNoticeTone.warning => (c.pendingWash, c.pending),
      KoloNoticeTone.critical => (c.failedWash, c.failed),
      KoloNoticeTone.highlight => (c.accentWash, c.accentText),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: KoloSpace.md,
        vertical: KoloSpace.md,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(KoloRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: KoloSpace.sm + 2),
          Expanded(
            child: Text(
              message,
              style: context.text.bodySmall?.copyWith(color: fg, height: 1.4),
            ),
          ),
          if (action != null) ...[const SizedBox(width: KoloSpace.sm), action!],
        ],
      ),
    );
  }
}

enum KoloNoticeTone { neutral, positive, warning, critical, highlight }

/// Member avatar with initials fallback.
///
/// A missing avatar must never leave a hole: initials on a tinted ground are
/// always renderable and always identify the person.
class KoloAvatar extends StatelessWidget {
  const KoloAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.size = 40,
    this.highlight = false,
  });

  final String name;
  final String? imageUrl;
  final double size;
  final bool highlight;

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bg = highlight ? c.accent : c.surfaceSunken;
    final fg = highlight ? c.accentOn : c.textSoft;

    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(color: c.hairline),
      ),
      child: Text(
        _initials,
        style: TextStyle(
          fontFamily: KoloType.family,
          fontSize: size * 0.36,
          fontWeight: FontWeight.w700,
          color: fg,
          letterSpacing: 0.2,
        ),
      ),
    );

    if (imageUrl == null || imageUrl!.isEmpty) return fallback;

    return ClipOval(
      child: Image.network(
        imageUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback,
      ),
    );
  }
}

/// A row of member avatars, overlapping, with an overflow count.
class KoloAvatarStack extends StatelessWidget {
  const KoloAvatarStack({
    super.key,
    required this.names,
    this.max = 4,
    this.size = 28,
  });

  final List<String> names;
  final int max;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shown = names.take(max).toList();
    final overflow = math.max(0, names.length - shown.length);

    return SizedBox(
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * (size * 0.68),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: c.surface, width: 2),
                ),
                child: KoloAvatar(name: shown[i], size: size),
              ),
            ),
          if (overflow > 0)
            Positioned(
              left: shown.length * (size * 0.68),
              child: Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.surfaceSunken,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.surface, width: 2),
                ),
                child: Text(
                  '+$overflow',
                  style: TextStyle(
                    fontFamily: KoloType.family,
                    fontSize: size * 0.32,
                    fontWeight: FontWeight.w700,
                    color: c.textSoft,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Small icon + label used for a metric inside a card.
class KoloMetric extends StatelessWidget {
  const KoloMetric({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.tone,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: c.textFaint),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                label.toUpperCase(),
                style: KoloType.eyebrow(c),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: KoloSpace.xs + 2),
        Text(
          value,
          style: KoloType.money(c, size: 16, weight: FontWeight.w600, color: tone ?? c.text),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// Bottom sheet with the design system's header treatment.
class KoloSheet extends StatelessWidget {
  const KoloSheet({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(KoloRadius.xl),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              KoloSpace.page,
              KoloSpace.md,
              KoloSpace.page,
              KoloSpace.xl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: c.hairline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: KoloSpace.xl),
                Text(title, style: context.text.headlineSmall),
                if (subtitle != null) ...[
                  const SizedBox(height: KoloSpace.xs + 2),
                  Text(
                    subtitle!,
                    style: context.text.bodySmall,
                  ),
                ],
                const SizedBox(height: KoloSpace.xl),
                child,
                if (actions != null) ...[
                  const SizedBox(height: KoloSpace.xl),
                  ...actions!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows a confirmation sheet and resolves to true when the member agrees.
Future<bool> koloConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final c = context.colors;
  final result = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => KoloSheet(
      title: title,
      child: Text(message, style: sheetContext.text.bodyMedium),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(sheetContext).pop(true),
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: c.failed, foregroundColor: Colors.white)
              : null,
          child: Text(confirmLabel),
        ),
        const SizedBox(height: KoloSpace.sm),
        OutlinedButton(
          onPressed: () => Navigator.of(sheetContext).pop(false),
          child: Text(cancelLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Transient feedback that never covers content it is talking about.
void koloToast(BuildContext context, String message, {bool isError = false}) {
  final c = context.colors;
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
            size: 18,
            color: isError ? c.failed : c.accent,
          ),
          const SizedBox(width: KoloSpace.sm + 2),
          Expanded(child: Text(message)),
        ],
      ),
      duration: const Duration(seconds: 4),
    ),
  );
}

/// A pill-shaped search field with a leading glyph.
///
/// Search in this product is always a filter on a list already on screen, never
/// a separate destination, so it sits inline and reads as part of the page.
class KoloSearchField extends StatelessWidget {
  const KoloSearchField({
    super.key,
    this.controller,
    this.hint = 'Search',
    this.onChanged,
    this.autofocus = false,
  });

  final TextEditingController? controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: 46,
      child: TextField(
      controller: controller,
      textAlignVertical: TextAlignVertical.center,
      onChanged: onChanged,
      autofocus: autofocus,
      style: TextStyle(
        fontFamily: KoloType.family,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: c.text,
      ),
      cursorColor: c.accentText,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: c.surfaceRaised,
        hintText: hint,
        hintStyle: TextStyle(
          fontFamily: KoloType.family,
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: c.textFaint,
        ),
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 14, right: 10),
          child: Icon(Icons.search_rounded, size: 17, color: c.textFaint),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 41, minHeight: 44),
        contentPadding: EdgeInsets.zero,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide(color: c.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide(color: c.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(999),
          borderSide: BorderSide(color: c.text.withValues(alpha: 0.35), width: 1.5),
        ),
      ),
      ),
    );
  }
}

/// A round, white, hairline-bordered icon button for a page header.
///
/// The circle is what makes it read as a separate control from the title beside
/// it; a bare glyph at header weight looks like punctuation.
class KoloIconAction extends StatelessWidget {
  const KoloIconAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: c.surfaceRaised,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: c.hairline),
            ),
            child: Icon(icon, size: 18, color: c.text),
          ),
        ),
      ),
    );
  }
}

/// The unread count on a conversation, as a citrus disc.
///
/// Citrus here is the same signal as the tab badge and the Home dot: something
/// is waiting for you. It is a count, not a decoration, so it only appears when
/// the number is above zero.
class KoloCountBadge extends StatelessWidget {
  const KoloCountBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      constraints: const BoxConstraints(minWidth: 17),
      height: 17,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: c.accent,
        borderRadius: BorderRadius.circular(9),
      ),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: KoloType.family,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: c.accentOn,
          height: 1.0,
        ),
      ),
    );
  }
}

/// A quiet explanatory block: a soft left rule, a glyph and a sentence.
///
/// Used for the honest asides a financial product owes its members — what is
/// not wired yet, what a number does not include. Deliberately not an alert:
/// no fill, no border box, no colour that suggests a problem.
class KoloNote extends StatelessWidget {
  const KoloNote({
    super.key,
    required this.message,
    this.icon = Icons.info_outline_rounded,
  });

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(KoloRadius.md),
        border: Border(left: BorderSide(color: KoloBrand.slate, width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 17, color: c.textSoft),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontFamily: KoloType.family,
                fontSize: 12.5,
                height: 1.5,
                color: c.textSoft,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A plain citrus text action, for the secondary affordance inside an empty or
/// error state. No fill, no border — the surrounding block already frames it.
class KoloTextAction extends StatelessWidget {
  const KoloTextAction({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: KoloSpace.md, vertical: 10),
        minimumSize: const Size(0, 40),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: KoloType.family,
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.14,
          color: c.accentText,
        ),
      ),
    );
  }
}

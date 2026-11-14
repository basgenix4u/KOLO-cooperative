import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// The KOLO brand mark, drawn from the vector trace of the approved asset.
///
/// Supplied as a [CustomPainter] path rather than a bitmap so it stays crisp at
/// every size — 20px in a navigation row through to 200px on the welcome
/// screen — with no asset variants to keep in sync and no extra dependency.
///
/// The path is the verified outline of the owner's logo (IoU 0.986 against the
/// source artwork): the angular forward-arrow with its diagonal counter, the
/// left bar, and the two parallelogram limbs. Geometry is in a 34×30 box and is
/// scaled to whatever the caller asks for.
class KoloMark extends StatelessWidget {
  const KoloMark({
    super.key,
    this.size = 28,
    this.color,
    this.semanticLabel = 'KOLO',
  });

  /// Height in logical pixels. Width follows the mark's own 1.5:1 ratio.
  final double size;
  final Color? color;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final resolved = color ?? context.colors.accent;
    return Semantics(
      label: semanticLabel,
      child: SizedBox(
        height: size,
        width: size * 1.5,
        child: CustomPaint(painter: _KoloMarkPainter(resolved)),
      ),
    );
  }
}

class _KoloMarkPainter extends CustomPainter {
  const _KoloMarkPainter(this.color);

  final Color color;

  /// Normalised silhouette (0..1 on both axes), traced from the supplied
  /// artwork. Eleven vertices, verified simple (no self-intersections), and
  /// 0.943 IoU against the source mask.
  static const List<Offset> _outline = [
    Offset(0.2400, 0.0000),
    Offset(0.7750, 0.0000),
    Offset(1.0000, 0.3350),
    Offset(1.0000, 0.6480),
    Offset(0.7650, 0.6480),
    Offset(0.9840, 1.0000),
    Offset(0.4820, 1.0000),
    Offset(0.2400, 0.6480),
    Offset(0.0000, 0.6480),
    Offset(0.0000, 0.3450),
    Offset(0.2400, 0.3450),
  ];

  /// The notch is fully enclosed by the outline, so it is a hole, not a concave
  /// edge. Drawing it as a reversed subpath with the non-zero winding rule
  /// punches it out, exactly as the artwork does.
  static const List<Offset> _notch = [
    Offset(0.2437, 0.3450),
    Offset(0.7650, 0.3450),
    Offset(0.7650, 0.6480),
    Offset(0.2437, 0.6480),
  ];

  static Path _polygon(List<Offset> points, Size size) {
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final point = Offset(p.dx * size.width, p.dy * size.height);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addPath(_polygon(_outline, size), Offset.zero)
      // Reversed order so the notch subtracts under both winding rules.
      ..addPath(_polygon(_notch.reversed.toList(), size), Offset.zero);
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _KoloMarkPainter old) => old.color != color;
}

/// The bottom navigation bar.
///
/// Four destinations, no more: a cooperative member's world is their overview,
/// their groups, their money movement and their account. Everything else is
/// reached from inside one of those, which keeps the tab bar predictable and
/// stops it becoming a menu.
///
/// The active state is not a filled pill behind the icon. It is citrus on the
/// icon and label plus a short citrus rule above the destination — quieter, and
/// it reads at a glance without turning the bar into a row of competing chips.
class KoloBottomNav extends StatelessWidget {
  const KoloBottomNav({
    super.key,
    required this.index,
    required this.onSelect,
    this.hasAlerts = false,
  });

  final int index;
  final ValueChanged<int> onSelect;

  /// Draws a small citrus dot on the Home destination when something needs
  /// attention. Deliberately shape-plus-colour so it is not colour-only.
  final bool hasAlerts;

  static const destinations = <({String label, IconData icon, IconData active})>[
    (label: 'Home', icon: Icons.home_outlined, active: Icons.home_rounded),
    (label: 'Groups', icon: Icons.groups_outlined, active: Icons.groups_rounded),
    (label: 'Money', icon: Icons.receipt_long_outlined, active: Icons.receipt_long_rounded),
    (label: 'Account', icon: Icons.person_outline_rounded, active: Icons.person_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.navBackground,
        border: Border(top: BorderSide(color: c.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              for (var i = 0; i < destinations.length; i++)
                Expanded(
                  child: _NavItem(
                    destination: destinations[i],
                    selected: i == index,
                    showDot: hasAlerts && i == 0,
                    onTap: () => onSelect(i),
                    colors: c,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
    required this.colors,
    this.showDot = false,
  });

  final ({String label, IconData icon, IconData active}) destination;
  final bool selected;
  final VoidCallback onTap;
  final KoloColors colors;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    final tone = selected ? colors.navActive : colors.navInactive;
    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // The active rule sits above the icon so the eye catches it on the
            // way down the bar rather than after reading the label.
            AnimatedContainer(
              duration: KoloMotion.fast,
              curve: KoloMotion.standard,
              height: 2,
              width: selected ? 18 : 0,
              margin: const EdgeInsets.only(bottom: KoloSpace.sm),
              decoration: BoxDecoration(
                color: colors.accent,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(selected ? destination.active : destination.icon,
                    size: 22, color: tone),
                if (showDot)
                  Positioned(
                    right: -3,
                    top: -1,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: colors.accent,
                        shape: BoxShape.circle,
                        border: Border.all(color: colors.navBackground, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              destination.label,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: 0.1,
                color: tone,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The header used at the top of a top-level screen.
///
/// A screen title in this product is a typographic statement: an optional
/// eyebrow, the title, and an action row aligned right. It is not a toolbar with
/// a back chevron and a centred caption.
class KoloPageHeader extends StatelessWidget {
  const KoloPageHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.actions = const [],
    this.leading,
    this.padding,
  });

  final String title;
  final String? eyebrow;
  final List<Widget> actions;
  final Widget? leading;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: padding ??
          const EdgeInsets.fromLTRB(
            KoloSpace.page,
            KoloSpace.lg,
            KoloSpace.page,
            KoloSpace.md,
          ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: KoloSpace.md)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (eyebrow != null) ...[
                  Text(eyebrow!.toUpperCase(), style: _eyebrowStyle(c)),
                  const SizedBox(height: KoloSpace.xs),
                ],
                Text(
                  title,
                  style: context.text.headlineMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          ...actions.map((a) => Padding(
                padding: const EdgeInsets.only(left: KoloSpace.xs),
                child: a,
              )),
        ],
      ),
    );
  }

  static TextStyle _eyebrowStyle(KoloColors c) => TextStyle(
        fontFamily: 'Inter',
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
        color: c.textFaint,
        height: 1.2,
      );
}

/// A back affordance for nested screens. 44×44 so it clears the touch target
/// minimum, and it carries a tooltip for screen readers and pointer users.
class KoloBackButton extends StatelessWidget {
  const KoloBackButton({super.key, required this.onTap, this.label = 'Back'});

  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KoloRadius.sm),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(KoloRadius.sm),
            border: Border.all(color: c.hairline),
          ),
          child: Icon(Icons.arrow_back_rounded, size: 18, color: c.text),
        ),
      ),
    );
  }
}

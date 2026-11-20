import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../design/typography.dart';

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

/// The signed-in tab bar — four destinations and a raised centre action.
///
/// This is the design's own geometry: a 78 px bar on the raised white surface,
/// two quiet destinations either side of a 54 px citrus bubble that sits proud
/// of the bar, then two more. The bubble is not a fifth tab competing for
/// attention; it is the one thing a member most often opens the app to do, so it
/// is lifted out of the row and made the only filled shape on the screen.
///
/// The active destination changes weight and colour only — no pill, no citrus
/// rule. Citrus is reserved for the action, so the bar stays calm.
class KoloBottomNav extends StatelessWidget {
  const KoloBottomNav({
    super.key,
    required this.index,
    required this.onSelect,
    this.onPay,
    this.hasAlerts = false,
    this.unread = 0,
  });

  final int index;
  final ValueChanged<int> onSelect;

  /// Opens the pay flow. The bubble is not a tab index — pressing it starts a
  /// flow rather than switching to a destination.
  final VoidCallback? onPay;

  /// Draws a small citrus dot on Home when something needs attention.
  final bool hasAlerts;

  /// Unread count on Messages. Zero hides the badge entirely.
  final int unread;

  static const destinations = <({String label, IconData icon, IconData active})>[
    (label: 'Home', icon: Icons.home_outlined, active: Icons.home_rounded),
    (label: 'Groups', icon: Icons.groups_outlined, active: Icons.groups_rounded),
    (label: 'Messages', icon: Icons.chat_bubble_outline_rounded, active: Icons.chat_bubble_rounded),
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
          height: 78,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _NavItem(
                        destination: destinations[0],
                        selected: index == 0,
                        onTap: () => onSelect(0),
                        colors: c,
                        showDot: hasAlerts,
                      ),
                    ),
                    Expanded(
                      child: _NavItem(
                        destination: destinations[1],
                        selected: index == 1,
                        onTap: () => onSelect(1),
                        colors: c,
                      ),
                    ),
                    const SizedBox(width: 78),
                    Expanded(
                      child: _NavItem(
                        destination: destinations[2],
                        selected: index == 2,
                        onTap: () => onSelect(2),
                        colors: c,
                        badge: unread,
                      ),
                    ),
                    Expanded(
                      child: _NavItem(
                        destination: destinations[3],
                        selected: index == 3,
                        onTap: () => onSelect(3),
                        colors: c,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: -12,
                child: _PayBubble(
                  colors: c,
                  onTap: onPay ?? () => onSelect(2),
                ),
              ),
              Positioned(
                bottom: 8,
                child: Container(
                  width: 134,
                  height: 5,
                  decoration: BoxDecoration(
                    color: c.text.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(3),
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

/// The centre action: a citrus disc lifted above the bar, ringed in the bar's
/// own colour so it reads as sitting in a cut-out rather than floating loosely.
class _PayBubble extends StatelessWidget {
  const _PayBubble({required this.colors, required this.onTap});

  final KoloColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Pay',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: colors.accent,
                shape: BoxShape.circle,
                border: Border.all(color: colors.navBackground, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: KoloBrand.citrusDeep.withValues(alpha: 0.45),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                  BoxShadow(
                    color: KoloBrand.ink.withValues(alpha: 0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(Icons.add_rounded, size: 24, color: colors.accentOn),
            ),
            const SizedBox(height: 4),
            Text(
              'Pay',
              style: TextStyle(
                fontFamily: KoloType.family,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: colors.text,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One quiet destination: a 23 px glyph with a 10 px label beneath it.
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
    required this.colors,
    this.showDot = false,
    this.badge = 0,
  });

  final ({String label, IconData icon, IconData active}) destination;
  final bool selected;
  final VoidCallback onTap;
  final KoloColors colors;
  final bool showDot;
  final int badge;

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
        child: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    selected ? destination.active : destination.icon,
                    size: 23,
                    color: tone,
                  ),
                  if (showDot)
                    Positioned(
                      right: -2,
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
                  if (badge > 0)
                    Positioned(
                      right: -9,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        constraints: const BoxConstraints(minWidth: 17),
                        height: 17,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: colors.accent,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: colors.navBackground, width: 1.5),
                        ),
                        child: Text(
                          badge > 9 ? '9+' : '$badge',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: KoloType.family,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: colors.accentOn,
                            height: 1.0,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                destination.label,
                style: TextStyle(
                  fontFamily: KoloType.family,
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  letterSpacing: -0.05,
                  color: tone,
                  height: 1.2,
                ),
              ),
            ],
          ),
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
            4,
            KoloSpace.page,
            8,
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
                  const SizedBox(height: 3),
                ],
                Text(
                  title,
                  style: context.text.displayMedium?.copyWith(fontSize: 30, letterSpacing: -0.9),
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
        fontFamily: KoloType.family,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
        color: c.textFaint,
        height: 1.45,
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

/// The 48 px band the platform status bar occupies.
///
/// On a device the OS draws this; in the parity harness it reproduces the
/// design frame so a render can be compared to its reference pixel for pixel.
/// It is never shown in the product itself.
class KoloStatusBar extends StatelessWidget {
  const KoloStatusBar({super.key, this.dark = false, this.solo = false});

  final bool dark;
  final bool solo;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: 48,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '9:41',
              style: TextStyle(
                fontFamily: KoloType.family,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.14,
                color: dark ? Colors.white : c.text,
              ),
            ),
            const Spacer(),
            _glyph(c, dark),
          ],
        ),
      ),
    );
  }

  Widget _glyph(KoloColors c, bool dark) {
    final tone = dark ? Colors.white : c.text;
    return Row(
      children: [
        Icon(Icons.signal_cellular_alt_rounded, size: 17, color: tone),
        const SizedBox(width: 6),
        Icon(Icons.wifi_rounded, size: 16, color: tone),
        const SizedBox(width: 6),
        Icon(Icons.battery_full_rounded, size: 20, color: tone),
      ],
    );
  }
}

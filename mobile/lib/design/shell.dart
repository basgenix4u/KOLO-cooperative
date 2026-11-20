import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../design/navigation.dart';
import '../design/tokens.dart';

/// The signed-in frame: four destinations plus the centre action, each keeping
/// its own scroll position.
///
/// Implemented as a [StatefulShellRoute] so switching tabs preserves the state of
/// the tab you left — scrolling a long contributions list, tapping into a group
/// and coming back must not reset you to the top. Every tab is a real route, so
/// deep links and back gestures keep working.
class KoloShell extends StatelessWidget {
  const KoloShell({
    super.key,
    required this.navigationShell,
    this.hasAlerts = false,
    this.unread = 0,
  });

  final StatefulNavigationShell navigationShell;
  final bool hasAlerts;
  final int unread;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Each destination owns its own body; the shell contributes only the bar.
      body: navigationShell,
      bottomNavigationBar: KoloBottomNav(
        index: navigationShell.currentIndex,
        hasAlerts: hasAlerts,
        unread: unread,
        onPay: () => context.push('/contributions'),
        onSelect: (i) {
          navigationShell.goBranch(
            i,
            initialLocation: i == navigationShell.currentIndex,
          );
        },
      ),
    );
  }
}

/// Placeholder body used by the tabs that are still being rebuilt.
///
/// It is deliberately honest and on-brand rather than blank: a member who taps
/// Groups during the rebuild should see that the screen is being replaced, not
/// an empty white page or a crash.
class KoloInProgress extends StatelessWidget {
  const KoloInProgress({super.key, required this.title, this.note});

  final String title;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            KoloPageHeader(title: title),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(KoloSpace.section),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const KoloMark(size: 40),
                      const SizedBox(height: KoloSpace.xl),
                      Text(
                        note ?? 'This screen is being rebuilt.',
                        textAlign: TextAlign.center,
                        style: context.text.bodyMedium?.copyWith(color: c.textSoft),
                      ),
                    ],
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

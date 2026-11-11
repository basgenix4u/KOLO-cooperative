import 'package:flutter/material.dart';

import '../../core/api/api_exception.dart';
import '../../core/theme/kolo_theme.dart';

/// A card-shaped container used across the app so spacing stays consistent.
class KoloCard extends StatelessWidget {
  const KoloCard({super.key, required this.child, this.padding, this.onTap, this.color});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color ?? KoloColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: KoloColors.divider),
      ),
      child: child,
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: content,
      ),
    );
  }
}

/// A status pill. Colours are chosen by meaning, not by whatever the string is.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status, this.label});

  final String status;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _colorsFor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(
        label ?? humanise(status),
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }

  static (Color, Color) _colorsFor(String status) {
    return switch (status) {
      'active' || 'confirmed' || 'settled' || 'paid' || 'succeeded' || 'passed' || 'approved' =>
        (KoloColors.successSoft, KoloColors.success),
      'pending' || 'pending_approval' || 'awaiting_payment' || 'collecting' || 'processing' ||
      'scheduled' || 'submitted' || 'open' =>
        (KoloColors.warningSoft, KoloColors.warning),
      'overdue' || 'failed' || 'rejected' || 'cancelled' || 'shortfall' || 'defaulted' =>
        (KoloColors.dangerSoft, KoloColors.danger),
      'ready_for_payout' || 'payout_pending_approval' => (KoloColors.amberSoft, KoloColors.amber),
      _ => (KoloColors.cloud, KoloColors.inkSoft),
    };
  }
}

/// "payout_pending_approval" -> "Payout pending approval"
String humanise(String raw) {
  if (raw.isEmpty) return '';
  final words = raw.replaceAll('_', ' ').trim();
  return words[0].toUpperCase() + words.substring(1);
}

/// The single error presentation. Financial refusals are shown as a considered
/// explanation, not a red banner: "not enough has been collected yet" is the
/// system working, not a malfunction.
class ErrorNotice extends StatelessWidget {
  const ErrorNotice({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (error is ApiException) {
      final api = error as ApiException;
      final isRefusal = api.isFinancialRefusal;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isRefusal ? KoloColors.amberSoft : KoloColors.dangerSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isRefusal ? KoloColors.amber : KoloColors.danger, width: 0.6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  isRefusal ? Icons.info_outline_rounded : Icons.error_outline_rounded,
                  size: 20,
                  color: isRefusal ? KoloColors.warning : KoloColors.danger,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    api.userMessage,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: isRefusal ? KoloColors.ink : KoloColors.danger,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            if (onRetry != null && !isRefusal) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: onRetry, child: const Text('Try again')),
              ),
            ],
          ],
        ),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: KoloColors.dangerSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Text(
        'Something went wrong. Please try again.',
        style: TextStyle(color: KoloColors.danger, fontWeight: FontWeight.w500),
      ),
    );
  }
}

/// Empty states say what to do next, not just that there is nothing here.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(color: KoloColors.cloud, shape: BoxShape.circle),
              child: Icon(icon, size: 30, color: KoloColors.inkFaint),
            ),
            const SizedBox(height: 18),
            Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(message, style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

/// A labelled amount row, used for every money breakdown.
class AmountRow extends StatelessWidget {
  const AmountRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasise = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool emphasise;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: emphasise ? 15 : 14,
              fontWeight: emphasise ? FontWeight.w600 : FontWeight.w400,
              color: KoloColors.inkSoft,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: emphasise ? 17 : 14,
              fontWeight: emphasise ? FontWeight.w700 : FontWeight.w600,
              color: valueColor ?? KoloColors.ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// A progress bar that never implies more has been collected than actually has.
class CollectionProgress extends StatelessWidget {
  const CollectionProgress({super.key, required this.percent, this.height = 8});

  final double percent;
  final double height;

  @override
  Widget build(BuildContext context) {
    final clamped = percent.clamp(0.0, 100.0) / 100;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        value: clamped,
        minHeight: height,
        backgroundColor: KoloColors.divider,
        valueColor: AlwaysStoppedAnimation(
          clamped >= 1 ? KoloColors.success : KoloColors.indigo,
        ),
      ),
    );
  }
}

Future<void> showMessage(BuildContext context, String message, {bool isError = false}) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: isError ? KoloColors.danger : KoloColors.ink,
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:freshly_core/freshly_core.dart';

/// The load-shedding banner is the most South-Africa-specific piece of this
/// product. It answers the question a customer actually asks before booking a
/// clipper cut at 18:00 — "will there be power?" — before they have to ask it.
class LoadSheddingBanner extends StatelessWidget {
  const LoadSheddingBanner({required this.status, this.onFilterPressed, super.key});

  final GridStatus status;
  final VoidCallback? onFilterPressed;

  @override
  Widget build(BuildContext context) {
    if (!status.isActive) return const SizedBox.shrink();

    final window = status.nextWindowStart != null && status.nextWindowEnd != null
        ? '${formatSlot(status.nextWindowStart!)} – ${TimeOfDay.fromDateTime(status.nextWindowEnd!).format(context)}'
        : null;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: FreshlySpacing.md, vertical: FreshlySpacing.sm),
      padding: const EdgeInsets.all(FreshlySpacing.md),
      decoration: BoxDecoration(
        color: FreshlyColors.loadShedding.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(FreshlySpacing.radius),
        border: Border.all(color: FreshlyColors.loadShedding.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.bolt, color: FreshlyColors.loadShedding),
          const SizedBox(width: FreshlySpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(status.label,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                if (window != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('Next outage in your area: $window',
                        style: const TextStyle(fontSize: 13, color: FreshlyColors.inkMuted)),
                  ),
                if (status.forcesPowerFilter)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Showing pros with backup power only.',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),
          if (onFilterPressed != null && !status.forcesPowerFilter)
            TextButton(
              onPressed: onFilterPressed,
              child: const Text('Backup only'),
            ),
        ],
      ),
    );
  }
}

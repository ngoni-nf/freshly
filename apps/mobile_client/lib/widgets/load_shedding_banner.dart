import 'package:flutter/material.dart';
import 'package:freshly_core/freshly_core.dart';

/// Answers the question a customer actually asks before booking a clipper cut
/// at 18:00 — "will there be power?" — before they have to ask it.
class LoadSheddingBanner extends StatelessWidget {
  const LoadSheddingBanner(
      {required this.status, this.onFilterPressed, super.key});

  final GridStatus status;
  final VoidCallback? onFilterPressed;

  @override
  Widget build(BuildContext context) {
    if (!status.isActive) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final window = status.nextWindowStart != null &&
            status.nextWindowEnd != null
        ? '${formatSlot(status.nextWindowStart!)} – ${formatSlot(status.nextWindowEnd!).split(', ').last}'
        : null;
    final ink =
        isDark ? FreshlyColors.loadShedding : FreshlyColors.loadSheddingInk;

    return Container(
      margin: const EdgeInsets.fromLTRB(
          FreshlySpacing.md, FreshlySpacing.sm + 4, FreshlySpacing.md, 0),
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
      decoration: BoxDecoration(
        color:
            isDark ? const Color(0xFF2A1B10) : FreshlyColors.loadSheddingSoft,
        borderRadius: BorderRadius.circular(FreshlySpacing.radius),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: FreshlyColors.loadShedding,
              shape: BoxShape.circle,
            ),
            child: const Icon(FreshlyIcons.bolt, size: 20, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(status.label,
                    style: FreshlyType.style(15,
                        weight: FontWeight.w800, color: ink)),
                if (window != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('Next outage: $window',
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                if (status.forcesPowerFilter)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Showing pros with backup power only.',
                      style: FreshlyType.style(13,
                          weight: FontWeight.w700, color: ink),
                    ),
                  ),
              ],
            ),
          ),
          if (onFilterPressed != null && !status.forcesPowerFilter)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: ink),
              onPressed: onFilterPressed,
              child: const Text('Backup only'),
            ),
        ],
      ),
    );
  }
}

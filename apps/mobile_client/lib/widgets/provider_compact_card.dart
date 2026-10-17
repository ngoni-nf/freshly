import 'package:flutter/material.dart';
import 'package:freshly_core/freshly_core.dart';

import 'provider_photo.dart';

/// The rail card: photo first, because a customer choosing a barber is
/// choosing a haircut they can see.
class ProviderCompactCard extends StatelessWidget {
  const ProviderCompactCard(
      {required this.provider, required this.onTap, super.key});

  static const double width = 176;
  static const double height = 248;

  final ProviderSummary provider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final eta = provider.etaMinutes;
    return Semantics(
      button: true,
      label: '${provider.displayName}, rated '
          '${provider.rating.toStringAsFixed(1)}, from '
          '${provider.fromPrice.format(compact: true)}',
      child: SizedBox(
        width: width,
        child: Card(
          child: InkWell(
            onTap: onTap,
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 140,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ProviderPhoto(
                            name: provider.displayName,
                            url: provider.avatarUrl),
                        if (provider.hasPowerBackup)
                          const Positioned(
                            left: 8,
                            top: 8,
                            child: _PhotoTag(
                                icon: FreshlyIcons.bolt, label: 'Backup'),
                          ),
                        if (provider.isOnline)
                          const Positioned(
                              right: 10, top: 10, child: OnlineDot(size: 14)),
                        Positioned(
                          left: 8,
                          bottom: 8,
                          child: _PricePill(
                              'From ${provider.fromPrice.format(compact: true)}'),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                    child: Text(
                      provider.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                    child: RatingLabel(
                        rating: provider.rating, count: provider.ratingCount),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Text(
                      [
                        formatDistance(provider.distanceKm),
                        if (eta != null && !provider.isShop) formatEta(eta),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotoTag extends StatelessWidget {
  const _PhotoTag({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 4, 8, 4),
      decoration: BoxDecoration(
        color: FreshlyColors.obsidian.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: FreshlyColors.gold),
          const SizedBox(width: 3),
          Text(label,
              style: FreshlyType.style(11,
                  weight: FontWeight.w700, color: Colors.white)),
        ],
      ),
    );
  }
}

class _PricePill extends StatelessWidget {
  const _PricePill(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: FreshlyColors.mint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: FreshlyType.style(12,
              weight: FontWeight.w800, color: FreshlyColors.obsidian)),
    );
  }
}

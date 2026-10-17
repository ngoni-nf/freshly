import 'package:flutter/material.dart';
import 'package:freshly_core/freshly_core.dart';

import 'provider_photo.dart';

/// The list card used in search results and salon listings.
class ProviderCard extends StatelessWidget {
  const ProviderCard({required this.provider, required this.onTap, super.key});

  final ProviderSummary provider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final eta = provider.etaMinutes;
    final meta = [
      formatDistance(provider.distanceKm),
      if (eta != null && !provider.isShop) formatEta(eta),
      if (provider.completedJobs > 0) '${provider.completedJobs} jobs',
    ].join(' · ');

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 84,
                height: 84,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ProviderPhoto(
                      name: provider.displayName,
                      url: provider.avatarUrl,
                      borderRadius:
                          BorderRadius.circular(FreshlySpacing.radiusSmall + 2),
                    ),
                    if (provider.isOnline)
                      const Positioned(
                          right: 6, top: 6, child: OnlineDot(size: 13)),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(provider.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleMedium),
                    const SizedBox(height: 4),
                    RatingLabel(
                        rating: provider.rating, count: provider.ratingCount),
                    const SizedBox(height: 4),
                    Text(
                      provider.isShop && provider.shopAddress != null
                          ? provider.shopAddress!
                          : meta,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text('From ', style: text.bodySmall),
                        Text(provider.fromPrice.format(compact: true),
                            style: FreshlyType.style(15,
                                weight: FontWeight.w800,
                                color: Theme.of(context).colorScheme.primary)),
                        const Spacer(),
                        if (provider.hasPowerBackup)
                          const StatusPill(
                            label: 'Backup power',
                            icon: FreshlyIcons.bolt,
                            tone: FreshlyTone.warning,
                            dense: true,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

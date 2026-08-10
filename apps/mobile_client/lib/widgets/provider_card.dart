import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:freshly_core/freshly_core.dart';

class ProviderCard extends StatelessWidget {
  const ProviderCard({required this.provider, required this.onTap, super.key});

  final ProviderSummary provider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FreshlySpacing.radius),
        child: Padding(
          padding: const EdgeInsets.all(FreshlySpacing.md),
          child: Row(
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(FreshlySpacing.radius),
                    child: provider.avatarUrl != null
                        ? CachedNetworkImage(
                            imageUrl: provider.avatarUrl!,
                            width: 72, height: 72, fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                                width: 72, height: 72, color: FreshlyColors.mintSoft),
                          )
                        : Container(
                            width: 72, height: 72,
                            color: FreshlyColors.mintSoft,
                            child: Center(
                              child: Text(
                                provider.displayName.characters.first.toUpperCase(),
                                style: const TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w700,
                                    color: FreshlyColors.mintDark),
                              ),
                            ),
                          ),
                  ),
                  if (provider.isOnline)
                    Positioned(
                      right: 4, top: 4,
                      child: Container(
                        width: 12, height: 12,
                        decoration: BoxDecoration(
                          color: FreshlyColors.mint,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: FreshlySpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(provider.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                        ),
                        if (provider.hasPowerBackup)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: FreshlyColors.gold.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.battery_charging_full, size: 13, color: FreshlyColors.gold),
                                SizedBox(width: 3),
                                Text('Power',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: FreshlyColors.gold)),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded, size: 15, color: FreshlyColors.gold),
                        const SizedBox(width: 2),
                        Text(provider.rating.toStringAsFixed(1),
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        Text(' (${provider.ratingCount})',
                            style: const TextStyle(fontSize: 13, color: FreshlyColors.inkMuted)),
                        const Text('  ·  ', style: TextStyle(color: FreshlyColors.inkMuted)),
                        Text(formatDistance(provider.distanceKm),
                            style: const TextStyle(fontSize: 13, color: FreshlyColors.inkMuted)),
                        if (provider.etaMinutes != null) ...[
                          const Text('  ·  ', style: TextStyle(color: FreshlyColors.inkMuted)),
                          Text(formatEta(provider.etaMinutes),
                              style: const TextStyle(fontSize: 13, color: FreshlyColors.inkMuted)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text('From ${provider.fromPrice.format(compact: true)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, color: FreshlyColors.mintDark)),
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

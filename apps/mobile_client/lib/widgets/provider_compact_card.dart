import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:freshly_core/freshly_core.dart';

class ProviderCompactCard extends StatelessWidget {
  const ProviderCompactCard({required this.provider, required this.onTap, super.key});

  final ProviderSummary provider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FreshlySpacing.radius),
        child: Container(
          width: 160,
          padding: const EdgeInsets.all(FreshlySpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(FreshlySpacing.radius),
                    child: provider.avatarUrl != null
                        ? CachedNetworkImage(
                            imageUrl: provider.avatarUrl!,
                            width: double.infinity,
                            height: 100,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Container(
                                width: double.infinity,
                                height: 100,
                                color: FreshlyColors.mintSoft),
                          )
                        : Container(
                            width: double.infinity,
                            height: 100,
                            color: FreshlyColors.mintSoft,
                            child: Center(
                              child: Text(
                                provider.displayName.characters.first
                                    .toUpperCase(),
                                style: const TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.w700,
                                    color: FreshlyColors.mintDark),
                              ),
                            ),
                          ),
                  ),
                  if (provider.isOnline)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: FreshlyColors.mint,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  if (provider.hasPowerBackup)
                    Positioned(
                      left: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: Colors.black45,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.bolt,
                            size: 12, color: FreshlyColors.gold),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: FreshlySpacing.sm),
              Text(
                provider.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  const Icon(Icons.star_rounded, size: 14, color: FreshlyColors.gold),
                  const SizedBox(width: 2),
                  Text(
                    provider.rating.toStringAsFixed(1),
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                  Text(
                    ' (${provider.ratingCount})',
                    style: const TextStyle(fontSize: 11, color: FreshlyColors.inkMuted),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                'From ${provider.fromPrice.format(compact: true)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: FreshlyColors.mintDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

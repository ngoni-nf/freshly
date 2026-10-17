import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:freshly_core/freshly_core.dart';

/// A provider's photo, or their monogram until they upload one. The fallback
/// is the same art while loading and after a failure, so the card never
/// flashes between two different empty states.
class ProviderPhoto extends StatelessWidget {
  const ProviderPhoto({
    required this.name,
    required this.url,
    this.borderRadius = BorderRadius.zero,
    super.key,
  });

  final String name;
  final String? url;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final fallback = MonogramArt(name: name, borderRadius: borderRadius);
    if (url == null) return fallback;
    return ClipRRect(
      borderRadius: borderRadius,
      child: CachedNetworkImage(
        imageUrl: url!,
        fit: BoxFit.cover,
        placeholder: (_, __) => fallback,
        errorWidget: (_, __, ___) => fallback,
      ),
    );
  }
}

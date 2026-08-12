import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';

import '../../app/providers.dart';

final myReviewsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) => ref.watch(apiProvider).getMyReviews(),
);

class ReviewsScreen extends ConsumerWidget {
  const ReviewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviews = ref.watch(myReviewsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Client Reviews')),
      body: reviews.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, __) => Center(child: Text(err is ApiException ? err.message : 'Could not load reviews')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(FreshlySpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FreshlyIcons.star, size: 48, color: FreshlyColors.inkMuted),
                    SizedBox(height: FreshlySpacing.md),
                    Text(
                      'No reviews yet. Completed jobs will show up here once clients rate them.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: FreshlyColors.inkMuted, height: 1.4),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(FreshlySpacing.md),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: FreshlySpacing.sm),
            itemBuilder: (context, i) {
              final r = list[i];
              return _ReviewCard(review: r);
            },
          );
        },
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});
  final Map<String, dynamic> review;

  @override
  Widget build(BuildContext context) {
    final rating = (review['rating'] as num).toDouble();
    final tags = (review['tags'] as List? ?? []).cast<String>();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(FreshlySpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(review['author'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(formatDate(DateTime.parse(review['createdAt'] as String)),
                    style: const TextStyle(fontSize: 12, color: FreshlyColors.inkMuted)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: List.generate(5, (i) {
                return Icon(
                  i < rating ? FreshlyIcons.star : FreshlyIcons.star, // Simplified stars
                  size: 14,
                  color: i < rating ? FreshlyColors.gold : FreshlyColors.line,
                );
              }),
            ),
            if (review['comment'] != null && (review['comment'] as String).isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(review['comment'] as String, style: const TextStyle(height: 1.4)),
            ],
            if (tags.isNotEmpty) ...[
              const SizedBox(height: FreshlySpacing.sm),
              Wrap(
                spacing: 4,
                children: tags.map((t) => Chip(
                  label: Text(t, style: const TextStyle(fontSize: 10)),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                )).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

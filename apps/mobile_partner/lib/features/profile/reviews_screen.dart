import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';

import '../../app/providers.dart';
import '../../widgets/job_tile.dart' show JobTileSkeleton;

final myReviewsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) => ref.watch(apiProvider).getMyReviews(),
);

class ReviewsScreen extends ConsumerWidget {
  const ReviewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviews = ref.watch(myReviewsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Reviews')),
      body: reviews.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(FreshlySpacing.md),
          children: const [JobTileSkeleton(count: 4)],
        ),
        error: (err, __) => EmptyState(
          icon: FreshlyIcons.star,
          title: 'Reviews did not load',
          message: err is ApiException
              ? err.message
              : 'Check your connection and try again.',
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(myReviewsProvider),
        ),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: FreshlyIcons.star,
              title: 'No reviews yet',
              message: 'Clients rate you after each job. Their reviews will '
                  'show up here.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(FreshlySpacing.md),
            itemCount: list.length,
            separatorBuilder: (_, __) =>
                const SizedBox(height: FreshlySpacing.sm),
            itemBuilder: (context, i) => _ReviewCard(review: list[i]),
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
    final author = review['author'] as String;
    final comment = review['comment'] as String?;
    final text = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(FreshlySpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                FreshlyAvatar(name: author, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(author, style: text.titleMedium),
                      const SizedBox(height: 2),
                      Semantics(
                        label: '${rating.round()} out of 5 stars',
                        excludeSemantics: true,
                        child: Row(
                          children: List.generate(
                            5,
                            (i) => Icon(
                              FreshlyIcons.star,
                              size: 14,
                              color: i < rating
                                  ? FreshlyColors.gold
                                  : Theme.of(context).colorScheme.outline,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(formatDate(DateTime.parse(review['createdAt'] as String)),
                    style: text.bodySmall),
              ],
            ),
            if (comment != null && comment.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(comment, style: text.bodyMedium),
            ],
            if (tags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: tags
                    .map((t) => StatusPill(label: t, tone: FreshlyTone.brand))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

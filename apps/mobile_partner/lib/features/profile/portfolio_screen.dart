import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/providers.dart';

class PortfolioScreen extends ConsumerStatefulWidget {
  const PortfolioScreen({super.key});

  @override
  ConsumerState<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends ConsumerState<PortfolioScreen> {
  bool _uploading = false;

  Future<void> _pickAndUpload() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2000,
      imageQuality: 85,
    );
    if (image == null) return;

    setState(() => _uploading = true);
    try {
      final bytes = await image.readAsBytes();
      final api = ref.read(apiProvider);

      // 1. Get signed URL
      final instruction = await api.getUploadUrl('image/jpeg');

      // 2. Upload to storage
      await api.uploadFile(instruction.url, bytes, 'image/jpeg');

      // 3. Register in database
      await api.addPortfolioItem(mediaKey: instruction.key);

      ref.invalidate(myPortfolioProvider);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _delete(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove photo?'),
        content: const Text('This photo will be removed from your portfolio.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: FreshlyColors.crimson),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(apiProvider).removePortfolioItem(id);
      ref.invalidate(myPortfolioProvider);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final portfolio = ref.watch(myPortfolioProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Portfolio'),
        actions: [
          if (_uploading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(
              icon: const Icon(FreshlyIcons.addPhoto),
              onPressed: _pickAndUpload,
              tooltip: 'Add photo',
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: portfolio.when(
        loading: () => GridView.count(
          padding: const EdgeInsets.all(FreshlySpacing.md),
          crossAxisCount: 3,
          crossAxisSpacing: FreshlySpacing.sm,
          mainAxisSpacing: FreshlySpacing.sm,
          children: List.generate(
              6, (_) => const Skeleton(radius: FreshlySpacing.radiusSmall)),
        ),
        error: (err, __) => EmptyState(
          icon: FreshlyIcons.gallery,
          title: 'Your photos did not load',
          message: err is ApiException ? err.message : err.toString(),
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(myPortfolioProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return EmptyState(
              icon: FreshlyIcons.gallery,
              title: 'Show what you can do',
              message: 'Clients choose with their eyes. Add photos of your '
                  'best cuts, braids and sets.',
              actionLabel: 'Add your first photo',
              onAction: _uploading ? null : _pickAndUpload,
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(FreshlySpacing.md),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: FreshlySpacing.sm,
              mainAxisSpacing: FreshlySpacing.sm,
            ),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final item = items[i];
              return GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => GalleryViewer(
                        urls: items.map((p) => p.url).toList(),
                        initialIndex: i,
                      ),
                      fullscreenDialog: true,
                    ),
                  );
                },
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius:
                            BorderRadius.circular(FreshlySpacing.radiusSmall),
                        child: Image.network(
                          item.url,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => ColoredBox(
                            color:
                                Theme.of(context).colorScheme.surfaceContainer,
                            child: const Icon(FreshlyIcons.gallery,
                                color: FreshlyColors.inkMuted),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: IconButton(
                        tooltip: 'Remove photo',
                        icon: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color:
                                FreshlyColors.obsidian.withValues(alpha: 0.6),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(FreshlyIcons.delete,
                              color: Colors.white, size: 16),
                        ),
                        onPressed: () => _delete(item.id),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

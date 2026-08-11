
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
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
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final portfolio = ref.watch(myPortfolioProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Work'),
        actions: [
          if (_uploading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(
              icon: const Icon(Icons.add_a_photo_outlined),
              onPressed: _pickAndUpload,
              tooltip: 'Add photo',
            ),
        ],
      ),
      body: portfolio.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, __) => Center(child: Text(err.toString())),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(FreshlySpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.collections_outlined, size: 48, color: FreshlyColors.inkMuted),
                    const SizedBox(height: FreshlySpacing.md),
                    const Text(
                      'Your gallery is empty. Add photos of your work to show '
                      'clients what you can do.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: FreshlyColors.inkMuted, height: 1.4),
                    ),
                    const SizedBox(height: FreshlySpacing.lg),
                    FilledButton(
                      onPressed: _pickAndUpload,
                      child: const Text('Add your first photo'),
                    ),
                  ],
                ),
              ),
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
              return InkWell(
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
                        borderRadius: BorderRadius.circular(FreshlySpacing.radius / 2),
                        child: Image.network(item.url, fit: BoxFit.cover),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.white, size: 20),
                        style: IconButton.styleFrom(backgroundColor: Colors.black38),
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import 'job_providers.dart';

/// Screen B.11 — suggesting an extra mid-job.
///
/// The provider picks one of their own services; the client gets a prompt in
/// their app and the hold only grows once they approve. Nothing here can add
/// to what the client pays on its own, which is the whole point: a provider
/// can never raise the bill unilaterally.
class AddonScreen extends ConsumerStatefulWidget {
  const AddonScreen({required this.bookingId, super.key});
  final String bookingId;

  @override
  ConsumerState<AddonScreen> createState() => _AddonScreenState();
}

class _AddonScreenState extends ConsumerState<AddonScreen> {
  ProviderMenuItem? _picked;
  AddonRequest? _sent;
  bool _busy = false;
  String? _error;

  Future<void> _send() async {
    final item = _picked;
    if (item == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final request =
          await ref.read(apiProvider).requestAddon(widget.bookingId, item.id);
      if (!mounted) return;
      setState(() => _sent = request);
      // The job card's total changes once the client says yes; a refresh on
      // the way back is how the provider sees it without pulling.
      ref.invalidate(jobProvider(widget.bookingId));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = switch (e.code) {
            'addon_not_allowed' =>
              'You can suggest extras once the job has started.',
            _ => e.message,
          });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final menu = ref.watch(myMenuProvider);
    final text = Theme.of(context).textTheme;

    if (_sent != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Extra suggested')),
        body: Column(
          children: [
            Expanded(
              child: EmptyState(
                icon: FreshlyIcons.checkCircle,
                title: 'Sent to your client',
                message:
                    '${_sent!.name} for ${_sent!.price.format()} is waiting '
                    'for their approval in their app. It is added to the '
                    'job only once they say yes.',
              ),
            ),
            StickyActionBar(
              child: FilledButton(
                onPressed: () => context.pop(),
                child: const Text('Back to the job'),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Suggest an extra')),
      body: menu.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(FreshlySpacing.md),
          children: const [
            Skeleton(height: 84, radius: FreshlySpacing.radius),
            SizedBox(height: FreshlySpacing.sm),
            Skeleton(height: 84, radius: FreshlySpacing.radius),
            SizedBox(height: FreshlySpacing.sm),
            Skeleton(height: 84, radius: FreshlySpacing.radius),
          ],
        ),
        error: (e, __) => EmptyState(
          icon: FreshlyIcons.error,
          title: 'Your menu did not load',
          message: e is ApiException ? e.message : 'Try again in a moment.',
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(myMenuProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return EmptyState(
              icon: FreshlyIcons.category,
              title: 'No services on your menu',
              message: 'Add the services you offer and you can suggest '
                  'them as extras mid-job.',
              actionLabel: 'Edit menu',
              onAction: () => context.push('/menu'),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(FreshlySpacing.md,
                FreshlySpacing.xs, FreshlySpacing.md, FreshlySpacing.xl),
            children: [
              Text(
                'The client approves it in their app before anything is '
                'added to the job.',
                style: text.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: FreshlySpacing.md),
              for (final item in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: FreshlySpacing.sm),
                  child: _MenuChoice(
                    item: item,
                    selected: _picked?.id == item.id,
                    onTap: () => setState(() => _picked = item),
                  ),
                ),
              if (_error != null) ...[
                const SizedBox(height: FreshlySpacing.sm),
                Text(_error!,
                    style: FreshlyType.style(14,
                        weight: FontWeight.w600, color: FreshlyColors.crimson)),
              ],
            ],
          );
        },
      ),
      bottomNavigationBar: StickyActionBar(
        leading: _picked == null
            ? Text('Pick a service', style: text.bodyMedium)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_picked!.price.format(), style: text.headlineSmall),
                  Text(_picked!.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall),
                ],
              ),
        child: FilledButton(
          onPressed: _picked == null || _busy ? null : _send,
          child: _busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: FreshlyColors.obsidian))
              : const Text('Ask client'),
        ),
      ),
    );
  }
}

class _MenuChoice extends StatelessWidget {
  const _MenuChoice(
      {required this.item, required this.selected, required this.onTap});
  final ProviderMenuItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final edge = isDark ? FreshlyColors.mint : FreshlyColors.obsidian;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FreshlySpacing.radius),
          side: BorderSide(
              color: selected ? edge : scheme.outline, width: selected ? 2 : 1),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(FreshlySpacing.radius)),
          child: Padding(
            padding: const EdgeInsets.all(FreshlySpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.name,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(item.price.format(),
                              style: FreshlyType.style(15,
                                  weight: FontWeight.w800,
                                  color: scheme.primary)),
                          const SizedBox(width: 8),
                          StatusPill(
                              label: formatDuration(item.durationMinutes),
                              icon: FreshlyIcons.clock,
                              dense: true),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  selected ? FreshlyIcons.checkCircle : FreshlyIcons.addCircle,
                  color: selected ? edge : scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

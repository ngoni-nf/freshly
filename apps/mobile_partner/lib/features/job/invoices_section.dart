import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';

/// The two invoices a finished job produces, with a share button each.
///
/// The PDF is fetched through the API client so the auth header travels with
/// it, written to the app's own cache directory and handed to the system
/// share sheet. Nothing is kept: the next share fetches it again, which is
/// cheaper than a cleanup job nobody remembers to write.
class InvoicesSection extends ConsumerWidget {
  const InvoicesSection(
      {required this.bookingId, required this.isStaff, super.key});
  final String bookingId;

  /// A staff member did the work but the salon issued the invoice, so the
  /// label must not say "your".
  final bool isStaff;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoices = ref.watch(invoicesProvider(bookingId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(
          title: 'Invoices',
          padding: EdgeInsets.fromLTRB(4, 0, 4, FreshlySpacing.sm),
        ),
        invoices.when(
          loading: () => const Column(
            children: [
              Skeleton(height: 72, radius: FreshlySpacing.radius),
              SizedBox(height: FreshlySpacing.sm),
              Skeleton(height: 72, radius: FreshlySpacing.radius),
            ],
          ),
          error: (e, __) => Card(
            child: EmptyState(
              compact: true,
              icon: FreshlyIcons.receipt,
              title: 'Invoices are not ready yet',
              message: e is ApiException ? e.message : null,
              actionLabel: 'Try again',
              onAction: () => ref.invalidate(invoicesProvider(bookingId)),
            ),
          ),
          data: (list) {
            if (list.isEmpty) {
              return const Card(
                child: EmptyState(
                  compact: true,
                  icon: FreshlyIcons.receipt,
                  title: 'Invoices are being prepared',
                  message: 'They appear here a moment after the job closes.',
                ),
              );
            }
            return Column(
              children: [
                for (final inv in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: FreshlySpacing.sm),
                    child: _InvoiceCard(invoice: inv, isStaff: isStaff),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _InvoiceCard extends ConsumerStatefulWidget {
  const _InvoiceCard({required this.invoice, required this.isStaff});
  final Invoice invoice;
  final bool isStaff;

  @override
  ConsumerState<_InvoiceCard> createState() => _InvoiceCardState();
}

class _InvoiceCardState extends ConsumerState<_InvoiceCard> {
  bool _busy = false;

  String get _label => widget.invoice.isPlatformFee
      ? 'Freshly fee invoice'
      : widget.isStaff
          ? 'Salon invoice to client'
          : 'Your invoice to client';

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes =
          await ref.read(apiProvider).downloadInvoice(widget.invoice.id);
      if (bytes.isEmpty) {
        throw ApiException(
            'empty_invoice', 'The invoice could not be fetched.');
      }
      // The number is unique and already safe for a file name (letters,
      // digits and dashes), so the share sheet shows "FR-ZW-2026-000012.pdf".
      final file =
          File('${Directory.systemTemp.path}/${widget.invoice.number}.pdf');
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/pdf')],
        subject: 'Invoice ${widget.invoice.number}',
        sharePositionOrigin:
            box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } on IOException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not save the invoice on this phone.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inv = widget.invoice;
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconBadge(
                    icon: FreshlyIcons.receipt,
                    tone: inv.isPlatformFee
                        ? FreshlyTone.neutral
                        : FreshlyTone.brand,
                    size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleMedium),
                      const SizedBox(height: 2),
                      Text(formatDate(inv.issuedAt),
                          style: text.bodySmall?.copyWith(color: muted)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(inv.total.format(), style: text.titleMedium),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(inv.number,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(color: muted)),
                ),
                TextButton.icon(
                  onPressed: _busy ? null : _share,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.ios_share, size: 18),
                  label: const Text('Share PDF'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

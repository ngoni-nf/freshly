import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';

final invoicesProvider =
    FutureProvider.autoDispose.family<List<Invoice>, String>(
  (ref, bookingId) => ref.watch(apiProvider).invoices(bookingId),
);

/// Fetches the PDF through the API (so the auth header goes with it), writes
/// it to the temp directory and hands it to the system share sheet. The temp
/// file is the OS's to clean up; nothing about the booking is kept on disk
/// anywhere the app reads back from.
Future<void> shareInvoice(WidgetRef ref, Invoice invoice) async {
  final bytes = await ref.read(apiProvider).downloadInvoice(invoice.id);
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/${invoice.number}.pdf');
  await file.writeAsBytes(bytes, flush: true);
  await Share.shareXFiles(
    [
      XFile(file.path,
          mimeType: 'application/pdf', name: '${invoice.number}.pdf')
    ],
    subject: 'Freshly invoice ${invoice.number}',
  );
}

/// The invoices for a completed booking, each with a share button.
///
/// The client sees only the invoice their pro issued them; the platform's fee
/// invoice goes to the provider. The server enforces that, so this just
/// renders whatever comes back.
class InvoiceList extends ConsumerWidget {
  const InvoiceList({required this.bookingId, super.key});
  final String bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoices = ref.watch(invoicesProvider(bookingId));
    final text = Theme.of(context).textTheme;

    return invoices.when(
      loading: () => const Skeleton(height: 76, radius: FreshlySpacing.radius),
      error: (e, __) => Card(
        child: Padding(
          padding: const EdgeInsets.all(FreshlySpacing.md),
          child: Row(children: [
            Expanded(
              child: Text(
                  e is ApiException ? e.message : 'Your invoice did not load.',
                  style: text.bodyMedium),
            ),
            TextButton(
              onPressed: () => ref.invalidate(invoicesProvider(bookingId)),
              child: const Text('Retry'),
            ),
          ]),
        ),
      ),
      data: (list) {
        if (list.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(FreshlySpacing.md),
              child: Row(children: [
                const IconBadge(
                    icon: FreshlyIcons.receipt,
                    size: 36,
                    tone: FreshlyTone.neutral),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                      'Your invoice appears here a moment after the job is '
                      'marked complete.',
                      style: text.bodySmall),
                ),
              ]),
            ),
          );
        }
        return Card(
          child: Column(children: [
            for (var i = 0; i < list.length; i++) ...[
              if (i > 0)
                Divider(
                    indent: 64, color: Theme.of(context).colorScheme.outline),
              _InvoiceRow(invoice: list[i]),
            ],
          ]),
        );
      },
    );
  }
}

class _InvoiceRow extends ConsumerStatefulWidget {
  const _InvoiceRow({required this.invoice});
  final Invoice invoice;

  @override
  ConsumerState<_InvoiceRow> createState() => _InvoiceRowState();
}

class _InvoiceRowState extends ConsumerState<_InvoiceRow> {
  bool _busy = false;

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await shareInvoice(ref, widget.invoice);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not open the share sheet. Try again.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inv = widget.invoice;
    final text = Theme.of(context).textTheme;
    return ListTile(
      leading: const IconBadge(
          icon: FreshlyIcons.receipt, size: 36, tone: FreshlyTone.brand),
      title: Text(
          inv.isPlatformFee ? 'Platform fee invoice' : 'Invoice from your pro',
          style: text.titleMedium),
      // The number is a thing people copy into an email, so it gets a line
      // to itself rather than wrapping mid-way.
      subtitle: Text(
          '${inv.number}\n${formatDate(inv.issuedAt)} · ${inv.total.format()}'),
      isThreeLine: true,
      trailing: _busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2))
          : OutlinedButton(
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 14)),
              onPressed: _share,
              child: const Text('Share'),
            ),
    );
  }
}

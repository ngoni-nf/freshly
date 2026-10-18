import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../widgets/business_form.dart';

/// The same form as sign-up, prefilled from the server, saving only what
/// changed.
class BusinessEditScreen extends ConsumerStatefulWidget {
  const BusinessEditScreen({super.key});

  @override
  ConsumerState<BusinessEditScreen> createState() => _BusinessEditScreenState();
}

class _BusinessEditScreenState extends ConsumerState<BusinessEditScreen> {
  BusinessDraft? _draft;
  ProviderBusiness? _original;
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    final draft = _draft!;
    setState(() => _error = draft.problem);
    if (_error != null) return;

    final changes = draft.changesFrom(_original!);
    if (changes.isEmpty) {
      context.pop();
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).updateBusiness(changes);
      ref.invalidate(myBusinessProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Business details saved')));
        context.pop();
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.code == 'outside_service_area'
            ? 'Freshly is not live at that base yet. Keep a base somewhere '
                'we cover.'
            : e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final business = ref.watch(myBusinessProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Business details')),
      body: business.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(FreshlySpacing.lg),
          children: const [
            Skeleton(width: 160, height: 22),
            SizedBox(height: 12),
            Skeleton(height: 56, radius: FreshlySpacing.buttonRadius),
            SizedBox(height: 12),
            Skeleton(height: 48, radius: FreshlySpacing.buttonRadius),
            SizedBox(height: FreshlySpacing.lg),
            Skeleton(width: 160, height: 22),
            SizedBox(height: 12),
            Skeleton(height: 120, radius: FreshlySpacing.radius),
          ],
        ),
        error: (e, __) => EmptyState(
          icon: FreshlyIcons.error,
          title: 'Your details did not load',
          message: e is ApiException
              ? e.message
              : 'Check your connection and try again.',
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(myBusinessProvider),
        ),
        data: (data) {
          // Built once from the first load. A refetch after saving must not
          // wipe out what is being typed.
          _original ??= data;
          _draft ??= BusinessDraft.fromBusiness(data);
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(FreshlySpacing.lg,
                      FreshlySpacing.md, FreshlySpacing.lg, FreshlySpacing.lg),
                  children: [
                    BusinessForm(
                      draft: _draft!,
                      showBookingTypes: true,
                      api: ref.read(apiProvider),
                      countryCode: ref.read(countryCodeProvider),
                      onChanged: () => setState(() {
                        if (_error != null) _error = _draft!.problem;
                      }),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: FreshlySpacing.md),
                      InlineError(message: _error!),
                    ],
                  ],
                ),
              ),
              StickyActionBar(
                child: FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(_busy ? 'Saving…' : 'Save changes'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

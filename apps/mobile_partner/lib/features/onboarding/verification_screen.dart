import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';

import '../../app/providers.dart';

/// Screen B.2 — identity verification.
///
/// This is the gate between signing up and being allowed to work, so the whole
/// design goal is to make the current state unambiguous. A provider who has
/// submitted documents and hears nothing assumes they were rejected and stops
/// opening the app; one who is rejected and is not told why resubmits the same
/// photograph three times.
class VerificationScreen extends ConsumerStatefulWidget {
  const VerificationScreen({super.key});

  @override
  ConsumerState<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends ConsumerState<VerificationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _idController = TextEditingController();
  final _nameController = TextEditingController();
  String _documentType = 'national_id';
  bool _busy = false;

  @override
  void dispose() {
    _idController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).submitKyc(
            documentType: _documentType,
            idNumber: _idController.text,
            fullName: _nameController.text,
          );
      ref.invalidate(kycStatusProvider);
      if (mounted) FocusScope.of(context).unfocus();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(kycStatusProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Verification')),
      body: status.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => Center(
          child: Text(
              e is ApiException ? e.message : 'Could not load your status'),
        ),
        data: (data) {
          final state = data['status'] as String? ?? 'unstarted';
          final submission = data['latestSubmission'] as Map<String, dynamic>?;

          if (state == 'verified') {
            return const _StatusPanel(
              icon: Icons.verified_user,
              colour: FreshlyColors.mint,
              title: 'You are verified',
              body: 'You can go online and accept bookings.',
            );
          }

          if (state == 'pending' || state == 'in_review') {
            return _StatusPanel(
              icon: Icons.hourglass_top,
              colour: FreshlyColors.inkMuted,
              title: state == 'in_review'
                  ? 'A person is checking your documents'
                  : 'Your documents are being checked',
              body: 'This usually takes a few minutes, but can take longer if '
                  'someone needs to look at it. We will send you an SMS either way.',
            );
          }

          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(FreshlySpacing.md),
              children: [
                if (state == 'rejected' &&
                    submission?['rejectionReason'] != null) ...[
                  Card(
                    color: FreshlyColors.crimson.withValues(alpha: 0.08),
                    child: ListTile(
                      leading: const Icon(Icons.error_outline,
                          color: FreshlyColors.crimson),
                      title: const Text('Not verified'),
                      subtitle: Text(submission!['rejectionReason'] as String),
                    ),
                  ),
                  const SizedBox(height: FreshlySpacing.md),
                ],
                const Text(
                  'We check your identity against the national register before you '
                  'can accept bookings. Clients are told that every professional '
                  'has been verified, and that has to be true.',
                  style: TextStyle(color: FreshlyColors.inkMuted, height: 1.4),
                ),
                const SizedBox(height: FreshlySpacing.lg),
                DropdownButtonFormField<String>(
                  initialValue: _documentType,
                  decoration: const InputDecoration(labelText: 'Document'),
                  items: const [
                    DropdownMenuItem(
                        value: 'national_id', child: Text('National ID')),
                    DropdownMenuItem(
                        value: 'passport', child: Text('Passport')),
                    DropdownMenuItem(
                        value: 'drivers_licence',
                        child: Text("Driver's licence")),
                  ],
                  onChanged: (v) =>
                      setState(() => _documentType = v ?? 'national_id'),
                ),
                const SizedBox(height: FreshlySpacing.md),
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Full name',
                    helperText: 'Exactly as it appears on the document',
                  ),
                  validator: (v) => (v == null || v.trim().length < 2)
                      ? 'Enter your full name'
                      : null,
                ),
                const SizedBox(height: FreshlySpacing.md),
                TextFormField(
                  controller: _idController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]'))
                  ],
                  decoration:
                      const InputDecoration(labelText: 'Document number'),
                  validator: (v) => (v == null || v.trim().length < 5)
                      ? 'Enter the number on the document'
                      : null,
                ),
                const SizedBox(height: FreshlySpacing.sm),
                const Text(
                  'Your ID number is encrypted. Only the last four digits are ever '
                  'shown, to you or to us.',
                  style: TextStyle(
                      color: FreshlyColors.inkMuted, fontSize: 12, height: 1.4),
                ),
                const SizedBox(height: FreshlySpacing.lg),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child:
                      Text(_busy ? 'Submitting…' : 'Submit for verification'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.icon,
    required this.colour,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color colour;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FreshlySpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: colour),
            const SizedBox(height: FreshlySpacing.md),
            Text(title,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: FreshlySpacing.sm),
            Text(body,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: FreshlyColors.inkMuted, height: 1.4)),
          ],
        ),
      ),
    );
  }
}

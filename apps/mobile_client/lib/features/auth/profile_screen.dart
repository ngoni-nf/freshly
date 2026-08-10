import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  bool _terms = false;
  bool _privacy = false;
  bool _marketing = false;
  bool _busy = false;
  String? _error;

  bool get _valid => _name.text.trim().length >= 2 && _terms && _privacy;

  Future<void> _submit() async {
    setState(() { _busy = true; _error = null; });
    try {
      await ref.read(apiProvider).completeProfile(
            fullName: _name.text.trim(),
            email: _email.text.trim().isEmpty ? null : _email.text.trim(),
            acceptTerms: _terms,
            acceptPrivacy: _privacy,
            acceptMarketing: _marketing,
          );
      final state = ref.read(authStateProvider);
      if (state is AuthNeedsProfile) {
        ref.read(authStateProvider.notifier).profileCompleted(state.session);
      }
      if (mounted) context.go('/auth/permissions');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Almost there')),
      body: ListView(
        padding: const EdgeInsets.all(FreshlySpacing.lg),
        children: [
          Text('Tell us who you are',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: FreshlySpacing.lg),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Full name'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: FreshlySpacing.md),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email (optional)',
              helperText: 'Used to send you invoices after each booking',
            ),
          ),
          const SizedBox(height: FreshlySpacing.lg),
          CheckboxListTile(
            value: _terms,
            onChanged: (v) => setState(() => _terms = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text('I accept the Freshly Terms of Service'),
          ),
          CheckboxListTile(
            value: _privacy,
            onChanged: (v) => setState(() => _privacy = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text('I have read the Privacy Notice'),
            subtitle: const Text(
              'How we collect, use and protect your personal information under POPIA.',
            ),
          ),
          CheckboxListTile(
            value: _marketing,
            onChanged: (v) => setState(() => _marketing = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text('Send me offers and updates (optional)'),
          ),
          if (_error != null) ...[
            const SizedBox(height: FreshlySpacing.md),
            Text(_error!, style: const TextStyle(color: FreshlyColors.crimson)),
          ],
          const SizedBox(height: FreshlySpacing.lg),
          FilledButton(
            onPressed: _valid && !_busy ? _submit : null,
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }
}

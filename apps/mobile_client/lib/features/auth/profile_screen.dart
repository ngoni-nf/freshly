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
    setState(() {
      _busy = true;
      _error = null;
    });
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
    final law = ref.watch(countryCodeProvider) == 'ZW'
        ? 'the Cyber and Data Protection Act'
        : 'POPIA';

    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            FreshlySpacing.lg, 0, FreshlySpacing.lg, FreshlySpacing.lg),
        children: [
          const ScreenIntro(
            eyebrow: 'Almost there',
            title: 'Tell us who you are',
            subtitle: 'We put your name on bookings and invoices.',
          ),
          const SizedBox(height: FreshlySpacing.xl),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.name],
            decoration: const InputDecoration(
              labelText: 'Full name',
              prefixIcon: Icon(FreshlyIcons.person),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(
              labelText: 'Email (optional)',
              helperText: 'For the invoice after each booking',
              prefixIcon: Icon(Icons.mail_outline),
            ),
          ),
          const SizedBox(height: FreshlySpacing.lg),
          Card(
            child: Column(
              children: [
                CheckboxListTile(
                  value: _terms,
                  onChanged: (v) => setState(() => _terms = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('I accept the Freshly Terms of Service'),
                ),
                const Divider(indent: 16, endIndent: 16),
                CheckboxListTile(
                  value: _privacy,
                  onChanged: (v) => setState(() => _privacy = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('I have read the Privacy Notice'),
                  subtitle: Text(
                    'How we collect, use and protect your personal '
                    'information under $law.',
                  ),
                ),
                const Divider(indent: 16, endIndent: 16),
                CheckboxListTile(
                  value: _marketing,
                  onChanged: (v) => setState(() => _marketing = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Send me offers and updates'),
                  subtitle: const Text('Optional. Turn off any time.'),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: FreshlySpacing.md),
            Text(_error!,
                style: FreshlyType.style(14,
                    weight: FontWeight.w600, color: FreshlyColors.crimson)),
          ],
        ],
      ),
      bottomNavigationBar: StickyActionBar(
        child: FilledButton(
          onPressed: _valid && !_busy ? _submit : null,
          child: _busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: FreshlyColors.obsidian))
              : const Text('Continue'),
        ),
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

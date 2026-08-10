import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';

class PhoneScreen extends ConsumerStatefulWidget {
  const PhoneScreen({super.key});

  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen> {
  final _controller = TextEditingController();
  String _country = 'ZA';
  bool _busy = false;
  String? _error;

  static const _markets = {
    'ZA': (prefix: '+27', digits: 9, label: 'South Africa', flag: '🇿🇦'),
    'ZW': (prefix: '+263', digits: 9, label: 'Zimbabwe', flag: '🇿🇼'),
  };

  bool get _valid {
    final digits = _controller.text
        .replaceAll(RegExp(r'\D'), '')
        .replaceFirst(RegExp(r'^0+'), '');
    return digits.length == _markets[_country]!.digits;
  }

  Future<void> _submit() async {
    if (!_valid || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).requestOtp(_controller.text, _country);
      ref.read(countryCodeProvider.notifier).state = _country;
      if (mounted) {
        unawaited(context.push('/auth/otp',
            extra: {'phone': _controller.text, 'countryCode': _country}));
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final market = _markets[_country]!;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FreshlySpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: FreshlySpacing.xl),
              Text('Welcome to Freshly',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: FreshlySpacing.sm),
              Text(
                'Enter your mobile number. We will send you a 6-digit code to sign in.',
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: FreshlyColors.inkMuted),
              ),
              const SizedBox(height: FreshlySpacing.xl),
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: FreshlyColors.line),
                      borderRadius:
                          BorderRadius.circular(FreshlySpacing.radius),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _country,
                        items: _markets.entries
                            .map((e) => DropdownMenuItem(
                                  value: e.key,
                                  child: Text(
                                      '${e.value.flag}  ${e.value.prefix}'),
                                ))
                            .toList(),
                        onChanged: (v) => setState(() => _country = v!),
                      ),
                    ),
                  ),
                  const SizedBox(width: FreshlySpacing.sm),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(market.digits + 1),
                      ],
                      decoration:
                          const InputDecoration(hintText: '82 123 4567'),
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _submit(),
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: FreshlySpacing.md),
                Text(_error!,
                    style: const TextStyle(color: FreshlyColors.crimson)),
              ],
              const Spacer(),
              Text(
                'By continuing you agree to the Freshly Terms and Privacy Notice. '
                'We process your information in line with POPIA.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: FreshlyColors.inkMuted),
              ),
              const SizedBox(height: FreshlySpacing.md),
              FilledButton(
                onPressed: _valid && !_busy ? _submit : null,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Send code'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

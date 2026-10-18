import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:freshly_core/freshly_core.dart';

/// How a mobile number is typed in each market we sign people up in.
///
/// Kept in one place so sign-in and a salon's staff invite accept the same
/// numbers in the same shape. The two screens drifting apart would mean a
/// number that signs in fine cannot be invited, or the other way round.
class PhoneMarket {
  const PhoneMarket({
    required this.prefix,
    required this.digits,
    required this.name,
    required this.hint,
  });

  final String prefix;

  /// Local digits after the leading zero is dropped.
  final int digits;
  final String name;
  final String hint;
}

const phoneMarkets = <String, PhoneMarket>{
  'ZW': PhoneMarket(
      prefix: '+263', digits: 9, name: 'Zimbabwe', hint: '77 123 4567'),
  'ZA': PhoneMarket(
      prefix: '+27', digits: 9, name: 'South Africa', hint: '82 123 4567'),
};

/// The local digits as typed, with a leading zero dropped. "077 123 4567" and
/// "77 123 4567" are the same number to everyone in Harare.
String localDigits(String raw) =>
    raw.replaceAll(RegExp(r'\D'), '').replaceFirst(RegExp(r'^0+'), '');

/// The number as the backend and Firebase expect it.
String toE164(String country, String raw) =>
    '${(phoneMarkets[country] ?? phoneMarkets['ZW']!).prefix}${localDigits(raw)}';

bool isCompleteNumber(String country, String raw) =>
    localDigits(raw).length ==
    (phoneMarkets[country] ?? phoneMarkets['ZW']!).digits;

/// A dialling-prefix picker beside a digits-only field.
class PhoneNumberField extends StatelessWidget {
  const PhoneNumberField({
    required this.country,
    required this.controller,
    required this.onCountryChanged,
    required this.onChanged,
    this.autofocus = false,
    super.key,
  });

  final String country;
  final TextEditingController controller;
  final ValueChanged<String> onCountryChanged;
  final ValueChanged<String> onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final market = phoneMarkets[country] ?? phoneMarkets['ZW']!;
    return Row(
      children: [
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(FreshlySpacing.buttonRadius),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: phoneMarkets.containsKey(country) ? country : 'ZW',
              borderRadius: BorderRadius.circular(FreshlySpacing.radius),
              icon: const Icon(FreshlyIcons.expandMore, size: 16),
              selectedItemBuilder: (_) => phoneMarkets.entries
                  .map((e) => Center(
                        child: Text(e.value.prefix,
                            style: FreshlyType.style(16,
                                weight: FontWeight.w700,
                                color: FreshlyColors.ink)),
                      ))
                  .toList(),
              items: phoneMarkets.entries
                  .map((e) => DropdownMenuItem(
                        value: e.key,
                        child: Text('${e.value.name}  ${e.value.prefix}'),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) onCountryChanged(v);
              },
            ),
          ),
        ),
        const SizedBox(width: FreshlySpacing.sm),
        Expanded(
          child: TextField(
            controller: controller,
            autofocus: autofocus,
            keyboardType: TextInputType.phone,
            style: FreshlyType.style(17,
                weight: FontWeight.w600, color: FreshlyColors.ink),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(market.digits + 1),
            ],
            decoration: InputDecoration(hintText: market.hint),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

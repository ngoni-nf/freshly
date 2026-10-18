import 'package:flutter/material.dart';
import 'package:freshly_core/freshly_core.dart';

/// Which legal document to show. The route carries the wire name.
enum LegalDoc {
  privacy,
  terms;

  static LegalDoc fromWire(String v) =>
      v == 'terms' ? LegalDoc.terms : LegalDoc.privacy;
}

/// The policy text, in the app, readable offline.
///
/// This is the plain-language version a person reads on their phone before
/// they hand over an address and a phone number. It is deliberately short and
/// deliberately honest: it says what Freshly does, not what a template says a
/// company might do. The lawyer-reviewed version replaces these sections in
/// place; nothing here invents a registration number, an address or a date
/// that does not exist yet.
class LegalScreen extends StatelessWidget {
  const LegalScreen({required this.doc, super.key});
  final LegalDoc doc;

  @override
  Widget build(BuildContext context) {
    final sections = switch (doc) {
      LegalDoc.privacy => _privacy,
      LegalDoc.terms => _terms,
    };
    final title = switch (doc) {
      LegalDoc.privacy => 'Privacy policy',
      LegalDoc.terms => 'Terms of service',
    };
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Scaffold(
      // The intro carries the title; the bar is only the way back.
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(FreshlySpacing.md, FreshlySpacing.sm,
            FreshlySpacing.md, FreshlySpacing.xl),
        children: [
          ScreenIntro(
            eyebrow: 'Freshly',
            title: title,
            subtitle: switch (doc) {
              LegalDoc.privacy => 'What we keep about you, why, and for how '
                  'long. Written to meet POPIA in South Africa and the Data '
                  'Protection Act in Zimbabwe.',
              LegalDoc.terms => 'The deal between you, the pro you book, and '
                  'Freshly, in plain words.',
            },
          ),
          const SizedBox(height: FreshlySpacing.lg),
          for (final s in sections) ...[
            Text(s.heading, style: text.titleMedium),
            const SizedBox(height: 6),
            Text(s.body, style: text.bodyMedium?.copyWith(height: 1.5)),
            const SizedBox(height: FreshlySpacing.md),
          ],
          const SizedBox(height: FreshlySpacing.sm),
          Text(
              'This is the plain-language version. If anything here is '
              'unclear, ask under Help and support and a person will answer.',
              style: text.bodySmall?.copyWith(color: muted)),
        ],
      ),
    );
  }
}

class _Section {
  const _Section(this.heading, this.body);
  final String heading;
  final String body;
}

const _privacy = [
  _Section(
    'Who we are',
    'Freshly is the on-demand beauty and grooming marketplace that runs this '
        'app in Zimbabwe and South Africa. Freshly is the responsible party '
        'under the Protection of Personal Information Act (POPIA) and the data '
        'controller under the Zimbabwe Data Protection Act for what this app '
        'collects.',
  ),
  _Section(
    'What we collect',
    'Your phone number and name, so a pro knows who booked and can reach you '
        'through the app. The address you book to, so the pro can get there. '
        'Your location while you use the app, so we can show pros who serve '
        'your area. Payment confirmations from the payment provider you choose; '
        'Freshly never sees or stores a full card number.',
  ),
  _Section(
    'What we do not keep',
    'A pro\'s live position during a job is held in memory only for the '
        'length of that job and expires on its own afterwards. It is never '
        'written to a database. Your address is shown to a pro only after they '
        'accept your booking; before that they see the suburb.',
  ),
  _Section(
    'Who sees it',
    'The pro you book sees your name, your address and your messages for '
        'that booking. The payment provider sees what it needs to take the '
        'payment. If you press SOS, your location and booking details go to '
        'the emergency response service for your market. Nobody else, and '
        'nothing is sold.',
  ),
  _Section(
    'Your rights',
    'You can ask what we hold about you, ask for it to be corrected, or ask '
        'for your account to be deleted. Ask under Help and support. Bookings '
        'and invoices are kept for as long as tax law in your country requires, '
        'then removed.',
  ),
];

const _terms = [
  _Section(
    'What Freshly is',
    'Freshly is a marketplace. The pro you book is an independent '
        'professional who sets their own prices and does the work. Freshly '
        'takes the booking, holds the payment, and pays the pro when the job '
        'is done.',
  ),
  _Section(
    'Paying',
    'You pay the price shown at checkout, which includes travel and the '
        'platform fee. The money is held, not taken, until your pro marks the '
        'job complete. A pro cannot add to the bill without you approving the '
        'extra in the app first.',
  ),
  _Section(
    'Your code',
    'Each booking has a four-digit code. You give it to your pro when they '
        'arrive; that is what starts the job and proves the person at your '
        'door is the person you booked. Do not share it with anyone else.',
  ),
  _Section(
    'Cancelling',
    'You can cancel for free up to the cancellation window shown for your '
        'market. Inside that window, or if you are not at the address when the '
        'pro arrives, part of the payment is kept to cover the pro\'s time.',
  ),
  _Section(
    'Problems',
    'If something goes wrong, report it from the booking before the payment '
        'is released and a person on the Freshly team will look at it with '
        'both sides. In an emergency use SOS, or call the emergency number for '
        'your market.',
  ),
];

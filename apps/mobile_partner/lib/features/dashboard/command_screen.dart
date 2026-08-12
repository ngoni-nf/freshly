import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';

/// Screen B.7 — the command dashboard.
///
/// The online toggle is the most important control in either app, so it gets
/// the top of the screen and an unmistakable state. A provider who thinks they
/// are online when they are not loses income silently and blames the platform,
/// which is exactly how supply churns.
class CommandScreen extends ConsumerWidget {
  const CommandScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(presenceProvider);
    final schedule = ref.watch(scheduleProvider);
    final wallet = ref.watch(walletProvider);
    final auth = ref.watch(partnerAuthProvider);
    final pending = auth is PartnerPendingVerification;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(scheduleProvider);
            ref.invalidate(walletProvider);
          },
          child: ListView(
            padding: const EdgeInsets.only(bottom: FreshlySpacing.xl),
            children: [
              Padding(
                padding: const EdgeInsets.all(FreshlySpacing.md),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Freshly Partner',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          Text(
                            isOnline
                                ? 'You are visible to clients'
                                : 'You are not taking jobs',
                            style: const TextStyle(
                                fontSize: 13, color: FreshlyColors.inkMuted),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => context.push('/portfolio'),
                      icon: const Icon(FreshlyIcons.gallery),
                      tooltip: 'My portfolio',
                    ),
                    IconButton(
                      onPressed: () => context.push('/clients'),
                      icon: const Icon(FreshlyIcons.people),
                      tooltip: 'My clients',
                    ),
                    IconButton(
                      onPressed: () => context.push('/menu'),
                      icon: const Icon(FreshlyIcons.style),
                      tooltip: 'My services',
                    ),
                    IconButton(
                      onPressed: () => context.push('/availability'),
                      icon: const Icon(FreshlyIcons.calendar),
                      tooltip: 'Availability',
                    ),
                  ],
                ),
              ),

              if (pending) const _VerificationBanner(),

              // ── Go online ────────────────────────────────────────────────
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: FreshlySpacing.md),
                child: _PresenceCard(
                  isOnline: isOnline,
                  enabled: !pending,
                  onChanged: (value) async {
                    try {
                      await ref
                          .read(presenceProvider.notifier)
                          .setOnline(value);
                    } on ApiException catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(e.message)));
                      }
                    }
                  },
                ),
              ),

              // ── Earnings ─────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.all(FreshlySpacing.md),
                child: wallet.when(
                  loading: () => const Card(
                    child: SizedBox(
                        height: 96,
                        child: Center(child: CircularProgressIndicator())),
                  ),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (data) => Card(
                    child: InkWell(
                      onTap: () => context.push('/wallet'),
                      borderRadius:
                          BorderRadius.circular(FreshlySpacing.radius),
                      child: Padding(
                        padding: const EdgeInsets.all(FreshlySpacing.md),
                        child: Row(
                          children: [
                            Expanded(
                              child: _Metric(
                                label: 'Available now',
                                value: formatMinor(
                                  (data['availableMinor'] as num?)?.toInt() ??
                                      0,
                                  data['currency'] as String? ?? 'ZAR',
                                ),
                                emphasis: true,
                              ),
                            ),
                            Container(
                                width: 1,
                                height: 40,
                                color: FreshlyColors.line),
                            Expanded(
                              child: _Metric(
                                label: 'Held in escrow',
                                value: formatMinor(
                                  (data['pendingMinor'] as num?)?.toInt() ?? 0,
                                  data['currency'] as String? ?? 'ZAR',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // ── Today ────────────────────────────────────────────────────
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: FreshlySpacing.md),
                child: Text('Today',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: FreshlySpacing.sm),
              schedule.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(FreshlySpacing.lg),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, __) => Padding(
                  padding: const EdgeInsets.all(FreshlySpacing.md),
                  child: Text(
                      e is ApiException
                          ? e.message
                          : 'Could not load your jobs',
                      style: const TextStyle(color: FreshlyColors.inkMuted)),
                ),
                data: (jobs) {
                  if (jobs.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(FreshlySpacing.md),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(FreshlySpacing.lg),
                          child: Column(
                            children: [
                              const Icon(FreshlyIcons.eventAvailable,
                                  size: 36, color: FreshlyColors.inkMuted),
                              const SizedBox(height: FreshlySpacing.sm),
                              Text(
                                isOnline
                                    ? 'No jobs yet. You will hear a request the moment one comes in.'
                                    : 'Go online to start receiving requests.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: FreshlyColors.inkMuted, height: 1.4),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  final instant =
                      jobs.where((j) => j['scheduledStart'] == null).toList();
                  final scheduled =
                      jobs.where((j) => j['scheduledStart'] != null).toList();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (instant.isNotEmpty) ...[
                        const Padding(
                          padding:
                              EdgeInsets.symmetric(horizontal: FreshlySpacing.md),
                          child: Text('Active now',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: FreshlyColors.mintDark)),
                        ),
                        const SizedBox(height: FreshlySpacing.xs),
                        ...instant.map((j) => _JobCard(job: j)),
                        const SizedBox(height: FreshlySpacing.md),
                      ],
                      if (scheduled.isNotEmpty) ...[
                        const Padding(
                          padding:
                              EdgeInsets.symmetric(horizontal: FreshlySpacing.md),
                          child: Text('Coming up',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: FreshlyColors.inkMuted)),
                        ),
                        const SizedBox(height: FreshlySpacing.xs),
                        ...scheduled.map((j) => _JobCard(job: j)),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({required this.job});
  final Map<String, dynamic> job;

  @override
  Widget build(BuildContext context) {
    final status = job['status'] as BookingStatus;
    final money = job['total'] as Money;
    final start = job['scheduledStart'] as DateTime?;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          FreshlySpacing.md, 0, FreshlySpacing.md, FreshlySpacing.sm),
      child: Card(
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: start == null
                ? FreshlyColors.mintSoft
                : FreshlyColors.inkMuted.withValues(alpha: 0.1),
            child: Text(
              start != null
                  ? TimeOfDay.fromDateTime(start)
                      .format(context)
                      .split(' ')
                      .first
                  : 'Now',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: start == null
                      ? FreshlyColors.mintDark
                      : FreshlyColors.inkMuted),
            ),
          ),
          title: Text(job['address'] as String,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${job['reference']} · ${status.clientLabel}'),
          trailing: Text(money.format(compact: true),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          onTap: () => context.push('/job/${job['id']}'),
        ),
      ),
    );
  }
}

class _PresenceCard extends StatelessWidget {
  const _PresenceCard(
      {required this.isOnline, required this.onChanged, required this.enabled});
  final bool isOnline;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: isOnline ? FreshlyColors.mintSoft : null,
      child: Padding(
        padding: const EdgeInsets.all(FreshlySpacing.md),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: isOnline ? FreshlyColors.mint : FreshlyColors.inkMuted,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: FreshlySpacing.md),
            Expanded(
              child: Text(
                isOnline ? 'Online' : 'Offline',
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
            Switch(
              value: isOnline,
              onChanged: enabled ? onChanged : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _VerificationBanner extends StatelessWidget {
  const _VerificationBanner();

  @override
  Widget build(BuildContext context) {
    // Tappable, because the banner is the only route to the one action that
    // unblocks the provider. A notice telling someone they are blocked, with
    // no way to act on it, is where onboarding quietly dies.
    return InkWell(
      onTap: () => context.push('/verification'),
      borderRadius: BorderRadius.circular(FreshlySpacing.radius),
      child: Container(
        margin: const EdgeInsets.symmetric(
            horizontal: FreshlySpacing.md, vertical: FreshlySpacing.sm),
        padding: const EdgeInsets.all(FreshlySpacing.md),
        decoration: BoxDecoration(
          color: FreshlyColors.gold.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(FreshlySpacing.radius),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(FreshlyIcons.verifiedOutline, color: FreshlyColors.gold),
            SizedBox(width: FreshlySpacing.sm),
            Expanded(
              child: Text(
                'Verify your identity to go online. You can set up your services '
                'in the meantime.',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
            ),
            Icon(FreshlyIcons.chevronRight, color: FreshlyColors.gold),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(
      {required this.label, required this.value, this.emphasis = false});
  final String label;
  final String value;
  final bool emphasis;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  const TextStyle(fontSize: 12, color: FreshlyColors.inkMuted)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                fontSize: emphasis ? 22 : 18,
                fontWeight: FontWeight.w700,
                color: emphasis ? FreshlyColors.mintDark : null,
              )),
        ],
      );
}

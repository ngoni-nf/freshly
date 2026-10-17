import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../widgets/job_status.dart';
import '../../widgets/job_tile.dart';

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
    final name = switch (auth) {
      PartnerReady(:final session) => session.fullName,
      PartnerPendingVerification(:final session) => session.fullName,
      _ => '',
    };
    final firstName = name.trim().split(' ').first;
    final text = Theme.of(context).textTheme;

    // The hero runs up behind the status bar, so the bar's icons turn light
    // over it and the hero pads itself by the inset SafeArea no longer adds.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: SafeArea(
          top: false,
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(scheduleProvider);
              ref.invalidate(walletProvider);
            },
            child: ListView(
              padding: const EdgeInsets.only(bottom: FreshlySpacing.xl),
              children: [
                ParallaxHero(
                  // The header itself says whether they are taking work: the
                  // brand shapes go grey the moment they are not.
                  accent:
                      isOnline ? FreshlyColors.mint : FreshlyColors.inkSubtle,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                        FreshlySpacing.md,
                        MediaQuery.paddingOf(context).top + FreshlySpacing.md,
                        FreshlySpacing.md,
                        FreshlySpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            FreshlyAvatar(
                                name: name.isEmpty ? 'Freshly' : name,
                                size: 44),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_greeting(),
                                      style: text.bodySmall?.copyWith(
                                          color: FreshlyColors.inkMuted)),
                                  Text(
                                      firstName.isEmpty
                                          ? 'Freshly Partner'
                                          : firstName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: text.titleLarge
                                          ?.copyWith(color: Colors.white)),
                                ],
                              ),
                            ),
                            _HeroIconButton(
                              icon: FreshlyIcons.calendar,
                              tooltip: 'Availability',
                              onPressed: () => context.push('/availability'),
                            ),
                          ],
                        ),
                        const SizedBox(height: FreshlySpacing.lg),
                        Text(
                          isOnline
                              ? 'You are visible\nto clients nearby.'
                              : 'You are not\ntaking jobs.',
                          style: text.displaySmall
                              ?.copyWith(color: Colors.white),
                        ),
                        const SizedBox(height: FreshlySpacing.lg),
                        // ── Go online ────────────────────────────────────
                        _PresenceControl(
                          isOnline: isOnline,
                          enabled: !pending,
                          onChanged: (value) async {
                            try {
                              await ref
                                  .read(presenceProvider.notifier)
                                  .setOnline(value);
                            } on ApiException catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(e.message)));
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                if (pending) const _VerificationBanner(),

                // ── Earnings and today at a glance ──────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(FreshlySpacing.md,
                      FreshlySpacing.md, FreshlySpacing.md, 0),
                  child: wallet.when(
                    loading: () => const Skeleton(
                        height: 96, radius: FreshlySpacing.radius),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (data) {
                      final currency = data['currency'] as String? ?? 'ZAR';
                      final jobsToday = schedule.valueOrNull?.length;
                      return Card(
                        child: InkWell(
                          onTap: () => context.push('/wallet'),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: FreshlySpacing.md),
                            child: SizedBox(
                              height: 52,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _Metric(
                                      label: 'Available',
                                      value: formatMinor(
                                        (data['availableMinor'] as num?)
                                                ?.toInt() ??
                                            0,
                                        currency,
                                      ),
                                      emphasis: true,
                                    ),
                                  ),
                                  const VerticalDivider(width: 1),
                                  Expanded(
                                    child: _Metric(
                                      label: 'In escrow',
                                      value: formatMinor(
                                        (data['pendingMinor'] as num?)
                                                ?.toInt() ??
                                            0,
                                        currency,
                                      ),
                                    ),
                                  ),
                                  const VerticalDivider(width: 1),
                                  Expanded(
                                    child: _Metric(
                                      label: 'Open jobs',
                                      value: jobsToday == null
                                          ? '--'
                                          : '$jobsToday',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // ── Jobs ─────────────────────────────────────────────────────
                const SizedBox(height: FreshlySpacing.lg),
                schedule.when(
                  loading: () => const Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: FreshlySpacing.md),
                    child: JobTileSkeleton(),
                  ),
                  error: (e, __) => EmptyState(
                    compact: true,
                    icon: FreshlyIcons.error,
                    title: 'Your jobs did not load',
                    message: e is ApiException
                        ? e.message
                        : 'Check your connection and try again.',
                    actionLabel: 'Try again',
                    onAction: () => ref.invalidate(scheduleProvider),
                  ),
                  data: (jobs) {
                    if (jobs.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: FreshlySpacing.md),
                        child: Card(
                          child: EmptyState(
                            compact: true,
                            icon: FreshlyIcons.eventAvailable,
                            title: isOnline
                                ? 'Waiting for your next job'
                                : 'No jobs right now',
                            message: isOnline
                                ? 'You will hear a request the moment one '
                                    'comes in.'
                                : 'Go online to start receiving requests.',
                          ),
                        ),
                      );
                    }

                    final instant =
                        jobs.where((j) => j['scheduledStart'] == null).toList();
                    final scheduled =
                        jobs.where((j) => j['scheduledStart'] != null).toList();
                    final next =
                        instant.isNotEmpty ? instant.first : scheduled.first;
                    final restInstant = instant.skip(1).toList();
                    final restScheduled = instant.isNotEmpty
                        ? scheduled
                        : scheduled.skip(1).toList();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionHeader(title: 'Next job'),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: FreshlySpacing.md),
                          child: _NextJobCard(job: next),
                        ),
                        if (restInstant.isNotEmpty) ...[
                          const SizedBox(height: FreshlySpacing.lg),
                          const SectionHeader(title: 'Active now'),
                          _JobList(jobs: restInstant),
                        ],
                        if (restScheduled.isNotEmpty) ...[
                          const SizedBox(height: FreshlySpacing.lg),
                          SectionHeader(
                            title: 'Coming up',
                            actionLabel: 'Schedule',
                            onAction: () => context.go('/schedule'),
                          ),
                          _JobList(jobs: restScheduled),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }
}

class _JobList extends StatelessWidget {
  const _JobList({required this.jobs});
  final List<Map<String, dynamic>> jobs;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FreshlySpacing.md),
      child: Column(
        children: [
          for (final j in jobs)
            Padding(
              padding: const EdgeInsets.only(bottom: FreshlySpacing.sm),
              child: JobTile(job: j),
            ),
        ],
      ),
    );
  }
}

/// The job the provider should be thinking about now, large enough to read
/// from a phone mount and with the one action it needs.
class _NextJobCard extends StatelessWidget {
  const _NextJobCard({required this.job});
  final Map<String, dynamic> job;

  @override
  Widget build(BuildContext context) {
    final status = job['status'] as BookingStatus;
    final money = job['total'] as Money;
    final start = job['scheduledStart'] as DateTime?;
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Card(
      child: InkWell(
        onTap: () => context.push('/job/${job['id']}'),
        child: Padding(
          padding: const EdgeInsets.all(FreshlySpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  StatusPill(
                    label: start == null ? 'Now' : formatSlot(start),
                    tone: start == null ? FreshlyTone.dark : FreshlyTone.info,
                    icon: start == null
                        ? FreshlyIcons.bolt
                        : FreshlyIcons.calendar,
                  ),
                  const SizedBox(width: 8),
                  StatusPill(label: status.partnerLabel, tone: status.tone),
                  const Spacer(),
                  Text(money.format(), style: text.titleLarge),
                ],
              ),
              const SizedBox(height: FreshlySpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const IconBadge(icon: FreshlyIcons.location, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(job['address'] as String,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleMedium),
                        const SizedBox(height: 2),
                        Text(job['reference'] as String,
                            style: text.bodySmall?.copyWith(color: muted)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: FreshlySpacing.md),
              ElevatedButton.icon(
                onPressed: () => context.push('/job/${job['id']}'),
                icon: const Icon(FreshlyIcons.navigation, size: 18),
                label: const Text('Open job'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The big online switch. A whole-width slab rather than a Material switch:
/// it is hit with a thumb at arm's length in the sun, and its state has to
/// be readable from the colour alone before the words are.
class _PresenceControl extends StatefulWidget {
  const _PresenceControl({
    required this.isOnline,
    required this.onChanged,
    required this.enabled,
  });

  final bool isOnline;
  final bool enabled;
  final Future<void> Function(bool) onChanged;

  @override
  State<_PresenceControl> createState() => _PresenceControlState();
}

class _PresenceControlState extends State<_PresenceControl> {
  bool _busy = false;

  Future<void> _toggle() async {
    if (_busy) return;
    unawaited(HapticFeedback.mediumImpact());
    setState(() => _busy = true);
    try {
      await widget.onChanged(!widget.isOnline);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final online = widget.isOnline;
    final enabled = widget.enabled;
    final fill = !enabled
        ? FreshlyColors.obsidianRaised
        : online
            ? FreshlyColors.mint
            : Colors.white;
    final ink = !enabled ? FreshlyColors.inkMuted : FreshlyColors.obsidian;

    final title = !enabled
        ? 'Verify to go online'
        : online
            ? 'You are online'
            : 'Go online';
    final subtitle = !enabled
        ? 'Identity check pending'
        : online
            ? 'Tap to go offline'
            : 'Start receiving job requests';

    return Semantics(
      button: true,
      toggled: online,
      enabled: enabled,
      label: title,
      excludeSemantics: true,
      child: Material(
        color: fill,
        borderRadius: BorderRadius.circular(FreshlySpacing.radius),
        child: InkWell(
          onTap: enabled ? _toggle : null,
          borderRadius: BorderRadius.circular(FreshlySpacing.radius),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: FreshlyType.style(20,
                              weight: FontWeight.w800, color: ink)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: FreshlyType.style(13,
                              weight: FontWeight.w500,
                              color: !enabled
                                  ? FreshlyColors.inkMuted
                                  : online
                                      ? FreshlyColors.mintInk
                                      : FreshlyColors.inkSubtle)),
                    ],
                  ),
                ),
                _Knob(online: online, enabled: enabled, busy: _busy),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Knob extends StatelessWidget {
  const _Knob({required this.online, required this.enabled, required this.busy});
  final bool online;
  final bool enabled;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final track = !enabled
        ? Colors.white.withValues(alpha: 0.08)
        : online
            ? FreshlyColors.obsidian
            : FreshlyColors.field;
    return Container(
      width: 64,
      height: 36,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: track,
        borderRadius: BorderRadius.circular(999),
      ),
      child: AnimatedAlign(
        duration: still ? Duration.zero : const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: online ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: !enabled
                ? FreshlyColors.inkSubtle
                : online
                    ? FreshlyColors.mint
                    : FreshlyColors.inkMuted,
            shape: BoxShape.circle,
          ),
          child: busy
              ? const Padding(
                  padding: EdgeInsets.all(7),
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: FreshlyColors.obsidian),
                )
              : !enabled
                  ? const Icon(FreshlyIcons.lock,
                      size: 14, color: FreshlyColors.obsidian)
                  : null,
        ),
      ),
    );
  }
}

class _HeroIconButton extends StatelessWidget {
  const _HeroIconButton(
      {required this.icon, required this.tooltip, required this.onPressed});
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.08),
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 48),
      ),
      icon: Icon(icon, size: 20),
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
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          FreshlySpacing.md, FreshlySpacing.md, FreshlySpacing.md, 0),
      child: Material(
        color: FreshlyColors.loadSheddingSoft,
        borderRadius: BorderRadius.circular(FreshlySpacing.radius),
        child: InkWell(
          onTap: () => context.push('/verification'),
          borderRadius: BorderRadius.circular(FreshlySpacing.radius),
          child: Padding(
            padding: const EdgeInsets.all(FreshlySpacing.md),
            child: Row(
              children: [
                const IconBadge(
                    icon: FreshlyIcons.verifiedOutline,
                    tone: FreshlyTone.warning,
                    size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Verify your identity',
                          style: text.titleSmall?.copyWith(
                              color: FreshlyColors.loadSheddingInk)),
                      const SizedBox(height: 2),
                      Text(
                        'You need this to go online. Set up your services in '
                        'the meantime.',
                        style: text.bodySmall
                            ?.copyWith(color: FreshlyColors.ink),
                      ),
                    ],
                  ),
                ),
                const Icon(FreshlyIcons.chevronRight,
                    size: 18, color: FreshlyColors.loadSheddingInk),
              ],
            ),
          ),
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
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: FreshlyType.style(emphasis ? 20 : 18,
                    weight: FontWeight.w800,
                    color: emphasis ? scheme.primary : scheme.onSurface)),
          ),
        ],
      ),
    );
  }
}

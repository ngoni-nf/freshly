import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';

import '../../app/providers.dart';
import '../../widgets/business_form.dart' show InlineError;
import '../../widgets/job_tile.dart' show JobTileSkeleton;
import '../../widgets/phone_field.dart';

/// Screen B.14 — the salon's team.
///
/// Staff are invited by number so someone who has never used Freshly can be
/// brought on. Money never reaches them through the app: every job on the
/// salon settles to the salon's wallet, and the owner squares up with their
/// people however they always have. The screen says so, because a stylist
/// who expects a wallet of their own will go looking for it.
class StaffScreen extends ConsumerWidget {
  const StaffScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staff = ref.watch(myStaffProvider);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Your team')),
      body: staff.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(FreshlySpacing.md),
          children: const [JobTileSkeleton(count: 3)],
        ),
        error: (e, __) => EmptyState(
          icon: FreshlyIcons.error,
          title: 'Your team did not load',
          message: switch (e) {
            ApiException(code: 'salon_only') =>
              'Teams are for salons. Your business is set up as solo.',
            ApiException(:final message) => message,
            _ => 'Check your connection and try again.',
          },
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(myStaffProvider),
        ),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: FreshlyIcons.people,
              title: 'No one on your team yet',
              message: 'Invite the people who work your chairs. Once they '
                  'have verified their identity you can hand them jobs '
                  'from your schedule.',
              actionLabel: 'Invite by phone',
              onAction: () => _InviteSheet.show(context),
            );
          }

          final active = list.where((s) => !s.isPending).toList();
          final invited = list.where((s) => s.isPending).toList();

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(myStaffProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  FreshlySpacing.md, FreshlySpacing.xs, FreshlySpacing.md, 96),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Jobs you assign go to their app. Payment still lands '
                    'in your wallet; you settle with your team as usual.',
                    style: text.bodySmall,
                  ),
                ),
                if (active.isNotEmpty) ...[
                  const SizedBox(height: FreshlySpacing.md),
                  _GroupLabel('${active.length} on the team'),
                  for (final s in active) _StaffRow(member: s),
                ],
                if (invited.isNotEmpty) ...[
                  const SizedBox(height: FreshlySpacing.md),
                  const _GroupLabel('Waiting to join'),
                  for (final s in invited) _StaffRow(member: s),
                ],
              ],
            ),
          );
        },
      ),
      floatingActionButton: staff.valueOrNull?.isNotEmpty ?? false
          ? FloatingActionButton.extended(
              heroTag: 'invite-staff',
              onPressed: () => _InviteSheet.show(context),
              icon: const Icon(FreshlyIcons.add),
              label: const Text('Invite by phone'),
            )
          : null,
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, FreshlySpacing.sm),
      child: Text(label.toUpperCase(),
          style: FreshlyType.style(12,
                  weight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)
              .copyWith(letterSpacing: 1)),
    );
  }
}

class _StaffRow extends ConsumerWidget {
  const _StaffRow({required this.member});
  final StaffMember member;

  String get _title => member.displayName?.trim().isNotEmpty == true
      ? member.displayName!
      : member.phoneMasked;

  Future<bool> _confirmRemove(BuildContext context, WidgetRef ref) async {
    final pending = member.isPending;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              FreshlySpacing.lg, 0, FreshlySpacing.lg, FreshlySpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const IconBadge(
                  icon: FreshlyIcons.delete,
                  tone: FreshlyTone.danger,
                  size: 52),
              const SizedBox(height: FreshlySpacing.md),
              Text(
                pending
                    ? 'Cancel this invitation?'
                    : 'Remove $_title from your team?',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                pending
                    ? '${member.phoneMasked} will no longer be able to join '
                        'with it. You can invite them again any time.'
                    : 'Any open jobs assigned to them come back to you. They '
                        'keep their Freshly account but cannot run jobs for '
                        'the salon.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: FreshlySpacing.lg),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: FreshlyColors.crimson,
                    foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(context, true),
                child: Text(pending ? 'Cancel invitation' : 'Remove'),
              ),
              const SizedBox(height: FreshlySpacing.xs),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep'),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true) return false;

    try {
      await ref.read(apiProvider).removeStaff(member.id);
      ref.invalidate(myStaffProvider);
      ref.invalidate(scheduleProvider);
      return true;
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.code == 'salon_only'
                ? 'Only a salon can manage a team.'
                : e.message)));
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final pending = member.isPending;

    return Padding(
      padding: const EdgeInsets.only(bottom: FreshlySpacing.sm),
      child: Dismissible(
        key: ValueKey('staff-${member.id}'),
        direction: DismissDirection.endToStart,
        confirmDismiss: (_) => _confirmRemove(context, ref),
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: FreshlySpacing.lg),
          decoration: BoxDecoration(
            color: FreshlyColors.crimsonSoft,
            borderRadius: BorderRadius.circular(FreshlySpacing.radius),
          ),
          child: const Icon(FreshlyIcons.delete,
              color: Color(0xFFB4232A), size: 22),
        ),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
            child: Row(
              children: [
                pending
                    ? const IconBadge(
                        icon: FreshlyIcons.mobile,
                        tone: FreshlyTone.neutral,
                        size: 48)
                    : FreshlyAvatar(name: _title, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleMedium),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          StatusPill(
                            label: pending ? 'Invited' : 'Active',
                            tone: pending
                                ? FreshlyTone.warning
                                : FreshlyTone.success,
                            dense: true,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              pending
                                  ? 'Waiting to accept'
                                  : '${member.jobsThisWeek} this week · '
                                      '${member.completedJobs} completed',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'More',
                  icon: Icon(Icons.more_horiz, color: scheme.onSurfaceVariant),
                  onSelected: (_) => _confirmRemove(context, ref),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'remove',
                      child: Text(
                          pending ? 'Cancel invitation' : 'Remove from team',
                          style: FreshlyType.style(15,
                              weight: FontWeight.w600,
                              color: FreshlyColors.crimson)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InviteSheet extends ConsumerStatefulWidget {
  const _InviteSheet();

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const _InviteSheet(),
      );

  @override
  ConsumerState<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends ConsumerState<_InviteSheet> {
  final _phone = TextEditingController();
  String _country = 'ZW';
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // A salon's staff work where the salon is; the picker is there for the
    // odd cross-border number, not as a question to answer every time.
    _country = ref.read(countryCodeProvider);
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy || !isCompleteNumber(_country, _phone.text)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final e164 = toE164(_country, _phone.text);
    try {
      await ref.read(apiProvider).inviteStaff(e164);
      if (!mounted) return;
      ref.invalidate(myStaffProvider);
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = switch (e.code) {
            'already_staff' => 'That number is already on your team.',
            'invite_pending' =>
              'You have already invited that number. They have not '
                  'accepted yet.',
            'has_own_business' =>
              'That number runs its own business on Freshly, so it cannot '
                  'join a team.',
            _ => e.message,
          });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final text = Theme.of(context).textTheme;
    final canSend = isCompleteNumber(_country, _phone.text) && !_busy;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              FreshlySpacing.lg, 0, FreshlySpacing.lg, FreshlySpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Invite by phone', style: text.headlineSmall),
              const SizedBox(height: 4),
              Text(
                'They will see your invitation when they open Freshly '
                'Partner with this number, or when they sign up with it.',
                style: text.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: FreshlySpacing.md),
              PhoneNumberField(
                country: _country,
                controller: _phone,
                autofocus: true,
                onCountryChanged: (v) => setState(() => _country = v),
                onChanged: (_) => setState(() => _error = null),
              ),
              if (_error != null) ...[
                const SizedBox(height: FreshlySpacing.sm),
                InlineError(message: _error!),
              ],
              const SizedBox(height: FreshlySpacing.md),
              FilledButton(
                onPressed: canSend ? _send : null,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: FreshlyColors.obsidian))
                    : const Text('Send invitation'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

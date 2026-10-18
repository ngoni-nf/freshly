import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';

import '../app/providers.dart';
import '../features/job/job_providers.dart';
import 'business_form.dart' show InlineError;

/// A booking can be handed to a team member while it is still ahead of them:
/// confirmed, accepted or on the way. Once someone is at the door it is
/// theirs.
bool canAssign(BookingStatus status) => const {
      BookingStatus.authorized,
      BookingStatus.accepted,
      BookingStatus.enRoute,
    }.contains(status);

/// Lets a salon owner pick who runs a job. Resolves true when the assignment
/// changed, so the caller can refresh whatever list it came from.
Future<bool> showAssignSheet(
  BuildContext context, {
  required String bookingId,
  required String? currentStaffId,
}) async {
  final changed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _AssignSheet(
      bookingId: bookingId,
      currentStaffId: currentStaffId,
    ),
  );
  return changed ?? false;
}

class _AssignSheet extends ConsumerStatefulWidget {
  const _AssignSheet({required this.bookingId, required this.currentStaffId});
  final String bookingId;
  final String? currentStaffId;

  @override
  ConsumerState<_AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends ConsumerState<_AssignSheet> {
  String? _busyFor;
  String? _error;

  Future<void> _assign(String? staffId) async {
    if (_busyFor != null) return;
    if (staffId == widget.currentStaffId) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() {
      _busyFor = staffId ?? 'self';
      _error = null;
    });
    try {
      await ref.read(apiProvider).assignBooking(widget.bookingId, staffId);
      ref.invalidate(jobProvider(widget.bookingId));
      ref.invalidate(scheduleProvider);
      ref.invalidate(myStaffProvider);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = switch (e.code) {
            'staff_unverified' =>
              'They have not finished identity verification yet. You can '
                  'hand them jobs as soon as they are verified.',
            'invalid_transition' ||
            'booking_not_assignable' =>
              'This job is too far along to reassign.',
            'salon_only' =>
              'Only a salon can hand out jobs. Your business is set up as '
                  'solo.',
            'not_your_booking' =>
              'This job is not on your salon\'s books, so it cannot be '
                  'assigned from here.',
            _ => e.message,
          });
    } finally {
      if (mounted) setState(() => _busyFor = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final staff = ref.watch(myStaffProvider);
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            FreshlySpacing.lg, 0, FreshlySpacing.lg, FreshlySpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Who is doing this job?', style: text.headlineSmall),
            const SizedBox(height: 4),
            Text(
              'It moves to their schedule and they run it from their app. '
              'Payment still comes to the salon.',
              style: text.bodyMedium?.copyWith(color: muted),
            ),
            const SizedBox(height: FreshlySpacing.md),
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.5),
              child: staff.when(
                loading: () => const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Skeleton(height: 64, radius: FreshlySpacing.radius),
                    SizedBox(height: FreshlySpacing.sm),
                    Skeleton(height: 64, radius: FreshlySpacing.radius),
                  ],
                ),
                error: (e, __) => EmptyState(
                  compact: true,
                  icon: FreshlyIcons.error,
                  title: 'Your team did not load',
                  message: e is ApiException ? e.message : null,
                  actionLabel: 'Try again',
                  onAction: () => ref.invalidate(myStaffProvider),
                ),
                data: (list) {
                  final active = list.where((s) => !s.isPending).toList();
                  return ListView(
                    shrinkWrap: true,
                    children: [
                      _Choice(
                        leading: const IconBadge(
                            icon: FreshlyIcons.person,
                            tone: FreshlyTone.dark,
                            size: 44),
                        title: 'Keep it myself',
                        subtitle: 'Stays on your own schedule',
                        selected: widget.currentStaffId == null,
                        busy: _busyFor == 'self',
                        onTap: () => _assign(null),
                      ),
                      for (final s in active)
                        Padding(
                          padding:
                              const EdgeInsets.only(top: FreshlySpacing.sm),
                          child: _Choice(
                            leading: FreshlyAvatar(
                                name: s.displayName ?? s.phoneMasked, size: 44),
                            title: s.displayName ?? s.phoneMasked,
                            subtitle: '${s.jobsThisWeek} this week',
                            selected: widget.currentStaffId == s.id,
                            busy: _busyFor == s.id,
                            onTap: () => _assign(s.id),
                          ),
                        ),
                      if (active.isEmpty)
                        Padding(
                          padding:
                              const EdgeInsets.only(top: FreshlySpacing.md),
                          child: Text(
                            'Nobody on your team has joined yet. Invite '
                            'them from Business, then come back here.',
                            textAlign: TextAlign.center,
                            style: text.bodySmall,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: FreshlySpacing.sm),
              InlineError(message: _error!),
            ],
          ],
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.busy,
    required this.onTap,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final bool selected;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final edge = isDark ? FreshlyColors.mint : FreshlyColors.obsidian;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FreshlySpacing.radius),
          side: BorderSide(
              color: selected ? edge : scheme.outline, width: selected ? 2 : 1),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(FreshlySpacing.radius)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(
                        selected
                            ? FreshlyIcons.checkCircle
                            : FreshlyIcons.chevronRight,
                        size: selected ? 22 : 16,
                        color: selected ? edge : scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

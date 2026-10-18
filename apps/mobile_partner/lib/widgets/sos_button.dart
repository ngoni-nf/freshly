import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/providers.dart';

/// Screen A.13c on the provider side: the floating SOS and everything after.
///
/// The number to dial when the alert cannot be sent comes from the market,
/// never from a constant. A Harare stylist told to ring a Johannesburg police
/// line is worse off than one told nothing.
class SosButton extends ConsumerStatefulWidget {
  const SosButton({this.bookingId, super.key});
  final String? bookingId;

  @override
  ConsumerState<SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends ConsumerState<SosButton> {
  String get _emergencyNumber =>
      ref.read(currentMarketProvider)?.emergencyNumber ?? '112';

  Future<void> _arm() async {
    unawaited(HapticFeedback.heavyImpact());
    final confirmed = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: FreshlyColors.crimson.withValues(alpha: 0.94),
      pageBuilder: (_, __, ___) => const _SosCountdown(),
    );
    if (confirmed != true || !mounted) return;

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.best),
      );
      final result = await ref.read(apiProvider).triggerSos(
            bookingId: widget.bookingId,
            lat: position.latitude,
            lng: position.longitude,
            accuracyM: position.accuracy,
          );
      if (!mounted) return;
      await showSosActiveSheet(
        context,
        sosId: result['id'] as String,
        dispatched: result['dispatched'] as bool? ?? true,
        emergencyNumber:
            result['emergencyNumber'] as String? ?? _emergencyNumber,
      );
    } on ApiException catch (e) {
      if (mounted) _couldNotSend(e.message);
    } catch (_) {
      // Location refused or unavailable. The alert is useless without a
      // position, and the person needs to dial rather than retry.
      if (mounted) _couldNotSend('your location could not be read');
    }
  }

  void _couldNotSend(String why) {
    final number = _emergencyNumber;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: FreshlyColors.crimson,
        duration: const Duration(seconds: 12),
        content: Text('Could not send alert: $why. Call $number now.'),
        action: SnackBarAction(
          label: 'Call $number',
          textColor: Colors.white,
          onPressed: () => dialEmergency(number),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      heroTag: 'sos',
      backgroundColor: FreshlyColors.crimson,
      foregroundColor: Colors.white,
      onPressed: _arm,
      tooltip: 'Emergency: send your location to the response team',
      icon: const Icon(FreshlyIcons.sos),
      label: Text('SOS',
          style: FreshlyType.style(16, weight: FontWeight.w800)
              .copyWith(letterSpacing: 1.5)),
    );
  }
}

/// Dials the market's public emergency line. This is the only number the
/// provider app ever places a call to: a client's number never leaves the
/// server, and the in-app chat is the way to reach them.
Future<void> dialEmergency(String number) async {
  final uri = Uri(scheme: 'tel', path: number);
  await launchUrl(uri);
}

/// Shown after an alert has gone out, and stays until the person says they
/// are safe. It cannot be swiped away: a sheet lost under a stray thumb
/// would leave a response team driving to someone who no longer needs them,
/// and nobody would know to stand them down.
Future<void> showSosActiveSheet(
  BuildContext context, {
  required String sosId,
  required bool dispatched,
  required String emergencyNumber,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      builder: (_) => SosActiveSheet(
        sosId: sosId,
        dispatched: dispatched,
        emergencyNumber: emergencyNumber,
      ),
    );

class SosActiveSheet extends ConsumerStatefulWidget {
  const SosActiveSheet({
    required this.sosId,
    required this.dispatched,
    required this.emergencyNumber,
    super.key,
  });

  final String sosId;

  /// False when no response service took the alert and only the person's
  /// emergency contacts were told. Then the copy says to dial, not to wait.
  final bool dispatched;
  final String emergencyNumber;

  @override
  ConsumerState<SosActiveSheet> createState() => _SosActiveSheetState();
}

class _SosActiveSheetState extends ConsumerState<SosActiveSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _standDown() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).abortSos(widget.sosId);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      // Already resolved by the operator is the one answer that means the
      // same as success: nobody is still coming.
      if (e.code == 'sos_already_resolved' || e.code == 'invalid_transition') {
        if (mounted) Navigator.of(context).pop();
        return;
      }
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return PopScope(
      canPop: false,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(FreshlySpacing.lg,
              FreshlySpacing.md, FreshlySpacing.lg, FreshlySpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              IconBadge(
                  icon: widget.dispatched
                      ? FreshlyIcons.checkCircle
                      : FreshlyIcons.warning,
                  tone: widget.dispatched
                      ? FreshlyTone.success
                      : FreshlyTone.danger,
                  size: 64),
              const SizedBox(height: FreshlySpacing.md),
              Text(
                widget.dispatched
                    ? 'Help is on the way'
                    : 'Alert logged. Call ${widget.emergencyNumber} now.',
                textAlign: TextAlign.center,
                style: text.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                widget.dispatched
                    ? 'Your location and trip details are with the response '
                        'team. Stay where you are if you can. This stays open '
                        'until you tell us you are safe.'
                    : 'No response unit could take this, so your emergency '
                        'contacts have your location. Ring the number below '
                        'if you are in danger.',
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: muted),
              ),
              const SizedBox(height: FreshlySpacing.lg),
              OutlinedButton.icon(
                onPressed: () => dialEmergency(widget.emergencyNumber),
                style: OutlinedButton.styleFrom(
                    foregroundColor: FreshlyColors.crimson,
                    side: const BorderSide(
                        color: FreshlyColors.crimson, width: 1.5)),
                icon: const Icon(FreshlyIcons.call, size: 18),
                label: Text('Call ${widget.emergencyNumber}'),
              ),
              const SizedBox(height: FreshlySpacing.sm),
              ElevatedButton(
                onPressed: _busy ? null : _standDown,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white))
                    : const Text('I am safe now'),
              ),
              if (_error != null) ...[
                const SizedBox(height: FreshlySpacing.sm),
                Text(
                  'Could not stand down: $_error. Try again, or tell the '
                  'response team when they reach you.',
                  textAlign: TextAlign.center,
                  style: text.bodySmall?.copyWith(color: FreshlyColors.crimson),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SosCountdown extends StatefulWidget {
  const _SosCountdown();

  @override
  State<_SosCountdown> createState() => _SosCountdownState();
}

class _SosCountdownState extends State<_SosCountdown> {
  int _seconds = 3;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      unawaited(HapticFeedback.heavyImpact());
      if (_seconds <= 1) {
        t.cancel();
        Navigator.of(context).pop(true);
      } else {
        setState(() => _seconds--);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FreshlySpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: FreshlySpacing.xl),
              const Icon(FreshlyIcons.sos, size: 40, color: Colors.white),
              const SizedBox(height: FreshlySpacing.md),
              Text('Emergency alert',
                  textAlign: TextAlign.center,
                  style: FreshlyType.style(24,
                      weight: FontWeight.w800, color: Colors.white)),
              const Spacer(),
              Center(
                child: Container(
                  width: 180,
                  height: 180,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.35), width: 6),
                  ),
                  child: Semantics(
                    liveRegion: true,
                    label: 'Sending in $_seconds',
                    excludeSemantics: true,
                    child: Text('$_seconds',
                        style: FreshlyType.style(96,
                            weight: FontWeight.w800,
                            height: 1,
                            color: Colors.white)),
                  ),
                ),
              ),
              const SizedBox(height: FreshlySpacing.lg),
              Text(
                'Sending your location and trip details to emergency response',
                textAlign: TextAlign.center,
                style: FreshlyType.style(18,
                    weight: FontWeight.w600, height: 1.4, color: Colors.white),
              ),
              const Spacer(),
              SizedBox(
                height: 72,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: FreshlyColors.crimson,
                  ),
                  onPressed: () {
                    _timer?.cancel();
                    Navigator.of(context).pop(false);
                  },
                  child: Text('Cancel',
                      style: FreshlyType.style(22, weight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

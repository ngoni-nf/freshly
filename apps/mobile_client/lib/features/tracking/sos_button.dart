import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';

/// The number to dial when SOS cannot be sent or is not enough: the police
/// line for the client's market, from the server, with a fallback that works
/// on any GSM network.
final emergencyNumberProvider = Provider<String>((ref) {
  final country = ref.watch(countryCodeProvider);
  final markets = ref.watch(marketsProvider).valueOrNull ?? const [];
  for (final m in markets) {
    if (m.code == country) return m.emergencyNumber;
  }
  return '112';
});

/// Screens A.13 / A.13c — the emergency control.
///
/// Two properties matter more than anything visual here. First, the abort
/// window is short and unmistakable: three seconds, full-screen, one large
/// cancel target — long enough to undo a pocket press, short enough to be
/// useful in a real incident. Second, the transmit path does not depend on the
/// websocket; it is a direct authenticated POST, because the situations where
/// someone presses this are exactly the situations where a socket has dropped.
class SosButton extends ConsumerStatefulWidget {
  const SosButton({this.bookingId, super.key});
  final String? bookingId;

  @override
  ConsumerState<SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends ConsumerState<SosButton> {
  Future<void> _arm() async {
    unawaited(HapticFeedback.heavyImpact());
    final confirmed = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: FreshlyColors.crimson.withValues(alpha: 0.94),
      pageBuilder: (_, __, ___) => const _SosCountdown(),
    );
    if (confirmed != true || !mounted) return;

    final emergencyNumber = ref.read(emergencyNumberProvider);
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
      if (mounted) {
        unawaited(SosActiveSheet.show(
          context,
          sosId: result['id'] as String?,
          dispatched: result['dispatched'] as bool? ?? true,
          message: result['message'] as String?,
          emergencyNumber:
              result['emergencyNumber'] as String? ?? emergencyNumber,
        ));
      }
    } on ApiException catch (e) {
      if (mounted) _failed(e.message, emergencyNumber);
    } catch (_) {
      // No position, no network, no anything: the one thing left is a
      // phone call, so put the number in front of them.
      if (mounted) _failed('No connection', emergencyNumber);
    }
  }

  void _failed(String reason, String emergencyNumber) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: FreshlyColors.crimson,
        duration: const Duration(seconds: 12),
        content: Text(
            'Could not send alert: $reason. Call $emergencyNumber directly.'),
        action: SnackBarAction(
          label: 'Call',
          textColor: Colors.white,
          onPressed: () => dialEmergency(emergencyNumber),
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
      icon: const Icon(FreshlyIcons.sos),
      label: const Text('SOS',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
    );
  }
}

Future<void> dialEmergency(String number) async {
  try {
    await launchUrl(Uri(scheme: 'tel', path: number));
  } catch (_) {
    // A tablet with no dialler. The number is printed on the button, so the
    // person can still dial it from something that has one.
  }
}

/// What stays on screen after the alert went out.
///
/// Persistent on purpose: a tap outside or a stray swipe must not make the
/// alert look dismissed when it is not. The two ways out are "I am safe now",
/// which stands the response team down, and keeping the alert open while
/// going back to the map. The phone number is a button, not a sentence.
class SosActiveSheet extends ConsumerStatefulWidget {
  const SosActiveSheet({
    required this.sosId,
    required this.dispatched,
    required this.emergencyNumber,
    this.message,
    super.key,
  });

  final String? sosId;
  final bool dispatched;
  final String emergencyNumber;
  final String? message;

  static Future<void> show(
    BuildContext context, {
    required String? sosId,
    required bool dispatched,
    required String emergencyNumber,
    String? message,
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
          message: message,
        ),
      );

  @override
  ConsumerState<SosActiveSheet> createState() => _SosActiveSheetState();
}

class _SosActiveSheetState extends ConsumerState<SosActiveSheet> {
  bool _busy = false;
  bool _stoodDown = false;
  String? _error;

  Future<void> _safe() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = widget.sosId;
      if (id != null) await ref.read(apiProvider).abortSos(id);
      if (!mounted) return;
      // The sheet stays up to say the stand-down went through. Popping on
      // success would look the same as popping on a mis-tap, and a person
      // who just pressed SOS needs to know which one happened.
      setState(() => _stoodDown = true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No connection. Try again in a moment.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final dispatched = widget.dispatched;
    if (_stoodDown) {
      return PopScope(
        canPop: false,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(FreshlySpacing.lg,
                FreshlySpacing.lg, FreshlySpacing.lg, FreshlySpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  const IconBadge(
                      icon: FreshlyIcons.checkCircle,
                      size: 52,
                      tone: FreshlyTone.success),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Alert stood down', style: text.headlineSmall),
                  ),
                ]),
                const SizedBox(height: FreshlySpacing.sm),
                Text(
                  'Glad you are safe. The response team has been told to '
                  'stand down. If anything changes, press SOS again.',
                  style: text.bodyMedium,
                ),
                const SizedBox(height: FreshlySpacing.lg),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return PopScope(
      canPop: false,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(FreshlySpacing.lg,
              FreshlySpacing.lg, FreshlySpacing.lg, FreshlySpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                IconBadge(
                    icon: dispatched
                        ? FreshlyIcons.checkCircle
                        : FreshlyIcons.warning,
                    size: 52,
                    tone:
                        dispatched ? FreshlyTone.success : FreshlyTone.danger),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                      dispatched ? 'Help is on the way' : 'Alert logged',
                      style: text.headlineSmall),
                ),
              ]),
              const SizedBox(height: FreshlySpacing.sm),
              Text(
                widget.message ??
                    (dispatched
                        ? 'Your location and trip details have been sent to '
                            'the response team. Stay where you are if you '
                            'can.'
                        : 'We logged your alert and told your emergency '
                            'contacts. Call ${widget.emergencyNumber} now if '
                            'you are in danger.'),
                style: text.bodyMedium,
              ),
              const SizedBox(height: FreshlySpacing.lg),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                    backgroundColor: FreshlyColors.crimson,
                    foregroundColor: Colors.white),
                onPressed: () => dialEmergency(widget.emergencyNumber),
                icon: const Icon(FreshlyIcons.call, size: 20),
                label: Text('Call ${widget.emergencyNumber}'),
              ),
              const SizedBox(height: FreshlySpacing.sm),
              FilledButton(
                onPressed: _busy ? null : _safe,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: FreshlyColors.obsidian))
                    : const Text('I am safe now'),
              ),
              if (_error != null) ...[
                const SizedBox(height: FreshlySpacing.sm),
                Text(_error!,
                    textAlign: TextAlign.center,
                    style: FreshlyType.style(14,
                        weight: FontWeight.w600, color: FreshlyColors.crimson)),
              ],
              const SizedBox(height: FreshlySpacing.xs),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Keep the alert open and go back'),
              ),
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
          padding: const EdgeInsets.all(FreshlySpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('$_seconds',
                  style: const TextStyle(
                      fontSize: 120,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
              const SizedBox(height: FreshlySpacing.md),
              const Text(
                'Sending your location to emergency response',
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 18, color: Colors.white, height: 1.4),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
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
                  child: const Text('CANCEL',
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
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

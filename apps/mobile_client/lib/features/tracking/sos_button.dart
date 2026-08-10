import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:geolocator/geolocator.dart';

import '../../app/providers.dart';

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
    HapticFeedback.heavyImpact();
    final confirmed = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: FreshlyColors.crimson.withValues(alpha: 0.94),
      pageBuilder: (_, __, ___) => const _SosCountdown(),
    );
    if (confirmed != true || !mounted) return;

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
      );
      await ref.read(apiProvider).triggerSos(
            bookingId: widget.bookingId,
            lat: position.latitude,
            lng: position.longitude,
            accuracyM: position.accuracy,
          );
      if (mounted) {
        showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            icon: const Icon(Icons.check_circle, color: FreshlyColors.mint, size: 40),
            title: const Text('Help is on the way'),
            content: const Text(
              'Your location and trip details have been sent to the response team. '
              'Stay on this screen if you can.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
            ],
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: FreshlyColors.crimson,
            content: Text('Could not send alert: ${e.message}. Call 10111 directly.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      heroTag: 'sos',
      backgroundColor: FreshlyColors.crimson,
      foregroundColor: Colors.white,
      onPressed: _arm,
      icon: const Icon(Icons.emergency_share),
      label: const Text('SOS', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
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
      HapticFeedback.heavyImpact();
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
                      fontSize: 120, fontWeight: FontWeight.w800, color: Colors.white)),
              const SizedBox(height: FreshlySpacing.md),
              const Text(
                'Sending your location to emergency response',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, color: Colors.white, height: 1.4),
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
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
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

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:geolocator/geolocator.dart';

import '../app/providers.dart';

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

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.best),
      );
      await ref.read(apiProvider).triggerSos(
            bookingId: widget.bookingId,
            lat: position.latitude,
            lng: position.longitude,
            accuracyM: position.accuracy,
          );
      if (mounted) {
        unawaited(showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            icon: const IconBadge(
                icon: FreshlyIcons.checkCircle,
                tone: FreshlyTone.success,
                size: 64),
            title: const Text('Help is on the way'),
            content: const Text(
              'Your location and trip details have been sent to the response team. '
              'Stay on this screen if you can.',
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close')),
            ],
          ),
        ));
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: FreshlyColors.crimson,
            content: Text(
                'Could not send alert: ${e.message}. Call emergency services directly.'),
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
      tooltip: 'Emergency: send your location to the response team',
      icon: const Icon(FreshlyIcons.sos),
      label: Text('SOS',
          style: FreshlyType.style(16, weight: FontWeight.w800)
              .copyWith(letterSpacing: 1.5)),
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

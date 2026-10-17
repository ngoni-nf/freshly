import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:freshly_core/freshly_core.dart';

/// Shown while the stored session is checked. Obsidian with the brand ring, so
/// the first frame after the native launch screen is already Freshly.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: FreshlyColors.obsidian,
        body: Stack(
          children: [
            Positioned(
              top: -120,
              right: -100,
              child: Container(
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: FreshlyColors.mint, width: 44),
                ),
              ),
            ),
            Positioned(
              bottom: -90,
              left: -70,
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: FreshlyColors.mint.withValues(alpha: 0.12),
                ),
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const FreshlyWordmark(size: 48),
                  const SizedBox(height: FreshlySpacing.sm),
                  Text('Look sharp, wherever you are.',
                      style: FreshlyType.style(16,
                          weight: FontWeight.w500,
                          color: FreshlyColors.inkMuted)),
                  const SizedBox(height: FreshlySpacing.xl),
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        color: FreshlyColors.mint, strokeWidth: 2),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

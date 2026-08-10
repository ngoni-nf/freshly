import 'package:flutter/material.dart';
import 'package:freshly_core/freshly_core.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: FreshlyColors.mint,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Freshly',
              style: TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -1,
              ),
            ),
            SizedBox(height: FreshlySpacing.sm),
            Text(
              'Freshness on demand.',
              style: TextStyle(fontSize: 16, color: Colors.white70),
            ),
            SizedBox(height: FreshlySpacing.xl),
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }
}

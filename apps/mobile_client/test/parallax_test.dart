import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freshly_core/freshly_core.dart';

/// A list whose first item is a parallax layer holding a tappable button,
/// followed by enough content to scroll.
Widget _harness({
  required ScrollController controller,
  required VoidCallback onPressed,
  double factor = 0.5,
  bool reduceMotion = false,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Scaffold(
        body: ListView(
          controller: controller,
          children: [
            SizedBox(
              height: 300,
              child: Parallax(
                factor: factor,
                // Centred, so it is still on screen after the tap test's
                // scroll. At the top-left it was pushed above the viewport
                // and the tap could never land, whatever the widget did.
                child: Align(
                  child: TextButton(
                    key: const Key('target'),
                    onPressed: onPressed,
                    child: const Text('Tap'),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2000),
          ],
        ),
      ),
    ),
  );
}

void main() {
  final target = find.byKey(const Key('target'));

  testWidgets('holds its child back by the factor as the list scrolls',
      (tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(
        _harness(controller: controller, onPressed: () {}, factor: 0.5));
    final before = tester.getTopLeft(target).dy;

    controller.jumpTo(100);
    await tester.pump();

    // The list moved up 100; half of that is given back, so the child moved
    // up only 50.
    expect(tester.getTopLeft(target).dy - before, closeTo(-50, 0.01));
  });

  testWidgets('stands still when the platform asks for reduced motion',
      (tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(_harness(
        controller: controller, onPressed: () {}, reduceMotion: true));
    final before = tester.getTopLeft(target).dy;

    controller.jumpTo(100);
    await tester.pump();

    expect(tester.getTopLeft(target).dy - before, closeTo(-100, 0.01));
  });

  testWidgets('taps land where the shifted child is drawn', (tester) async {
    final controller = ScrollController();
    var taps = 0;
    await tester.pumpWidget(
        _harness(controller: controller, onPressed: () => taps++, factor: 0.5));

    controller.jumpTo(120);
    await tester.pump();
    await tester.tap(target);

    expect(taps, 1);
  });

  testWidgets('ParallaxHero lays out its content and survives a scroll',
      (tester) async {
    final controller = ScrollController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(
          controller: controller,
          children: const [
            ParallaxHero(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Freshly'),
              ),
            ),
            SizedBox(height: 2000),
          ],
        ),
      ),
    ));
    expect(find.text('Freshly'), findsOneWidget);

    controller.jumpTo(150);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

import 'package:flutter/material.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:go_router/go_router.dart';

class MainScaffold extends StatelessWidget {
  const MainScaffold({required this.navigationShell, super.key});
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
              top: BorderSide(color: Theme.of(context).colorScheme.outline)),
        ),
        child: NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          // Tapping the current tab again returns to its root, as every
          // native app does.
          onDestinationSelected: (index) => navigationShell.goBranch(index,
              initialLocation: index == navigationShell.currentIndex),
          destinations: const [
            NavigationDestination(
                icon: Icon(FreshlyIcons.sparkles), label: 'Home'),
            NavigationDestination(
                icon: Icon(FreshlyIcons.search), label: 'Explore'),
            NavigationDestination(
                icon: Icon(FreshlyIcons.calendar), label: 'Bookings'),
            NavigationDestination(
                icon: Icon(FreshlyIcons.person), label: 'Profile'),
          ],
        ),
      ),
    );
  }
}

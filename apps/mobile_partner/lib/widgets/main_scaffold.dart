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
          onDestinationSelected: (index) => navigationShell.goBranch(index),
          destinations: const [
            NavigationDestination(
                icon: Icon(FreshlyIcons.nearMe), label: 'Today'),
            NavigationDestination(
                icon: Icon(FreshlyIcons.calendar), label: 'Schedule'),
            NavigationDestination(
                icon: Icon(FreshlyIcons.wallet), label: 'Earnings'),
            NavigationDestination(
                icon: Icon(FreshlyIcons.storefront), label: 'Business'),
          ],
        ),
      ),
    );
  }
}

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
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: navigationShell.currentIndex,
        onTap: (index) => navigationShell.goBranch(index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: FreshlyColors.mint,
        unselectedItemColor: FreshlyColors.inkMuted,
        selectedLabelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(FreshlyIcons.nearMe),
            activeIcon: Icon(FreshlyIcons.nearMe),
            label: 'Command',
          ),
          BottomNavigationBarItem(
            icon: Icon(FreshlyIcons.calendar),
            activeIcon: Icon(FreshlyIcons.calendar),
            label: 'Schedule',
          ),
          BottomNavigationBarItem(
            icon: Icon(FreshlyIcons.wallet),
            activeIcon: Icon(FreshlyIcons.wallet),
            label: 'Earnings',
          ),
          BottomNavigationBarItem(
            icon: Icon(FreshlyIcons.category),
            activeIcon: Icon(FreshlyIcons.category),
            label: 'Business',
          ),
        ],
      ),
    );
  }
}

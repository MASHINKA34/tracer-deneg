import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import '../../ui/components/bottom_nav.dart';

final _log = Logger('nav');

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  AppNavTab get _active => AppNavTab.values[navigationShell.currentIndex];

  void _selectTab(AppNavTab tab) {
    final from = _active;
    if (tab == from) {
      _log.fine('tab ${tab.name} tapped again → branch root');
    } else {
      _log.fine('tab ${from.name} → ${tab.name}');
    }
    navigationShell.goBranch(tab.index, initialLocation: tab == from);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: AppBottomNav(
        active: _active,
        onTabSelected: _selectTab,
        onAdd: null,
      ),
    );
  }
}

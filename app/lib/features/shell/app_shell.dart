import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import '../../core/router.dart';
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

  void _openNewExpense(BuildContext context) {
    _log.fine('new expense open from tab=${_active.name}');
    context.pushNamed(AppRoutes.newExpenseName);
  }

  void _handleBack(bool didPop, Object? result) {
    if (didPop) return;
    _log.fine('back on ${_active.name} root → ${AppNavTab.month.name}');
    navigationShell.goBranch(AppNavTab.month.index);
  }

  @override
  Widget build(BuildContext context) {
    final active = _active;
    return PopScope<Object?>(
      canPop: active == AppNavTab.month,
      onPopInvokedWithResult: _handleBack,
      child: Scaffold(
        extendBody: true,
        body: navigationShell,
        bottomNavigationBar: AppBottomNav(
          active: active,
          onTabSelected: _selectTab,
          onAdd: () => _openNewExpense(context),
        ),
      ),
    );
  }
}

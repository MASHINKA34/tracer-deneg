import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import '../../core/router.dart';
import '../../ui/components/bottom_nav.dart';
import '../expense/expense_snackbar_layer.dart';
import '../holidays/mood_controller.dart';

final _log = Logger('nav');

class AppShell extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final active = _active;
    final sticker = ref.watch(
      moodControllerProvider.select((today) => today.holiday?.key.emoji),
    );
    return PopScope<Object?>(
      canPop: active == AppNavTab.month,
      onPopInvokedWithResult: _handleBack,
      child: Scaffold(
        extendBody: true,
        body: navigationShell,
        bottomNavigationBar: ExpenseSnackbarAnchor(
          child: AppBottomNav(
            active: active,
            onTabSelected: _selectTab,
            onAdd: () => _openNewExpense(context),
            fabSticker: sticker,
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import '../../core/router.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/theme/app_theme.dart';
import '../categories/categories_top_bar.dart';

final _log = Logger('nav');

class RecurringEditorStubScreen extends StatefulWidget {
  const RecurringEditorStubScreen({super.key, this.ruleId});

  final String? ruleId;

  @override
  State<RecurringEditorStubScreen> createState() =>
      _RecurringEditorStubScreenState();
}

class _RecurringEditorStubScreenState extends State<RecurringEditorStubScreen> {
  String _closedBy = 'back';

  String get _target => widget.ruleId == null ? 'new' : 'id=${widget.ruleId}';

  @override
  void initState() {
    super.initState();
    _log.fine('recurring editor stub opened rule=$_target');
  }

  void _back() {
    _closedBy = 'back button';
    if (context.canPop()) {
      context.pop();
      return;
    }
    _log.fine(
      'recurring editor stub closed by back button with nothing under it → '
      '${AppRoutes.recurring}',
    );
    context.go(AppRoutes.recurring);
  }

  void _handlePop(bool didPop, Object? result) {
    if (!didPop) return;
    _log.fine('recurring editor stub rule=$_target closed by $_closedBy');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopScope<Object?>(
      onPopInvokedWithResult: _handlePop,
      child: Scaffold(
        backgroundColor: context.colors.bgApp,
        body: SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: CategoriesTopBar(
              title: l10n.recurringEditorTitle,
              onBack: _back,
            ),
          ),
        ),
      ),
    );
  }
}

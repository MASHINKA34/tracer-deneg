import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../../core/app_frame.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/snackbar.dart';
import 'expense_delete_controller.dart';

final _log = Logger('expense');

const Duration expenseSnackbarFade = Duration(milliseconds: 250);

const double expenseSnackbarSide = 12;

const double expenseSnackbarAboveAnchor = 21;

const double expenseSnackbarBottom = 12;

class ExpenseSnackbarLayer extends ConsumerStatefulWidget {
  const ExpenseSnackbarLayer({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ExpenseSnackbarLayer> createState() =>
      _ExpenseSnackbarLayerState();
}

class _ExpenseSnackbarLayerState extends ConsumerState<ExpenseSnackbarLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: expenseSnackbarFade,
  );
  final List<_ExpenseSnackbarAnchorState> _anchors = [];
  ExpenseSnack? _shown;

  @override
  void initState() {
    super.initState();
    _fade.addStatusListener(_onFade);
    ref.listenManual<ExpenseSnack?>(
      expenseDeleteProvider,
      _onSnack,
      fireImmediately: true,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final instant = MediaQuery.disableAnimationsOf(context);
    _fade
      ..duration = instant ? Duration.zero : expenseSnackbarFade
      ..reverseDuration = instant ? Duration.zero : expenseSnackbarFade;
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  void _onSnack(ExpenseSnack? previous, ExpenseSnack? next) {
    if (next == null) {
      if (_shown == null) return;
      if (_fade.isDismissed) {
        setState(() => _shown = null);
      } else {
        _fade.reverse();
      }
      return;
    }
    ScaffoldMessenger.maybeOf(context)?.removeCurrentSnackBar();
    setState(() => _shown = next);
    _fade.forward(from: 0);
  }

  void _onFade(AnimationStatus status) {
    if (status.isDismissed &&
        mounted &&
        ref.read(expenseDeleteProvider) == null) {
      setState(() => _shown = null);
    }
  }

  void _attach(_ExpenseSnackbarAnchorState anchor) {
    _anchors.add(anchor);
    _relayout();
  }

  void _detach(_ExpenseSnackbarAnchorState anchor) {
    _anchors.remove(anchor);
    _relayout();
  }

  void _relayout() {
    if (_shown == null) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  double _bottom(MediaQueryData media) {
    for (final anchor in _anchors.reversed) {
      if (!anchor.mounted) continue;
      final box = anchor.context.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      return math.max(
        media.size.height - top + expenseSnackbarAboveAnchor,
        media.viewPadding.bottom + expenseSnackbarBottom,
      );
    }
    return media.viewPadding.bottom + expenseSnackbarBottom;
  }

  void _undo() {
    final snack = ref.read(expenseDeleteProvider);
    if (snack is ExpenseUndoOffer) {
      _log.fine('expense undo tap id=${snack.expense.id} on snackbar');
    }
    ref.read(expenseDeleteProvider.notifier).undo();
  }

  Widget _snackbar(AppLocalizations l10n, ExpenseSnack shown) =>
      switch (shown) {
        ExpenseUndoOffer(:final expense) => AppSnackbar(
          text: l10n.expenseDeleted(expense.amount.format()),
          actionLabel: l10n.expenseDeleteUndo,
          onAction: _undo,
        ),
        ExpenseDeleteNotice(problem: ExpenseDeleteProblem.deleteFailed) =>
          AppSnackbar(text: l10n.expenseDeleteFailed),
        ExpenseDeleteNotice(problem: ExpenseDeleteProblem.undoFailed) =>
          AppSnackbar(text: l10n.expenseUndoFailed),
      };

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    final live = ref.watch(expenseDeleteProvider) != null;
    final media = MediaQuery.of(context);
    final left = contentLeftFor(media.size.width, media.padding);
    final right = media.size.width - left - contentWidthFor(media.size.width);
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (shown != null)
          Positioned(
            left: left + expenseSnackbarSide,
            right: right + expenseSnackbarSide,
            bottom: _bottom(media),
            child: IgnorePointer(
              ignoring: !live,
              child: FadeTransition(
                opacity: _fade,
                child: Semantics(
                  container: true,
                  liveRegion: true,
                  child: Material(
                    type: MaterialType.transparency,
                    child: _snackbar(AppLocalizations.of(context), shown),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class ExpenseSnackbarAnchor extends StatefulWidget {
  const ExpenseSnackbarAnchor({super.key, required this.child});

  final Widget child;

  @override
  State<ExpenseSnackbarAnchor> createState() => _ExpenseSnackbarAnchorState();
}

class _ExpenseSnackbarAnchorState extends State<ExpenseSnackbarAnchor> {
  _ExpenseSnackbarLayerState? _layer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final layer = context.findAncestorStateOfType<_ExpenseSnackbarLayerState>();
    if (layer == _layer) return;
    _layer?._detach(this);
    _layer = layer?.._attach(this);
  }

  @override
  void dispose() {
    _layer?._detach(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

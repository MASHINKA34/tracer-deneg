import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

final _log = Logger('sync');

enum BudgetRemovalKind { excluded, deleted }

final class BudgetRemovedNotice {
  const BudgetRemovedNotice({
    required this.id,
    required this.budgetId,
    required this.name,
    required this.kind,
  });

  final int id;
  final String budgetId;
  final String name;
  final BudgetRemovalKind kind;

  @override
  String toString() => 'BudgetRemovedNotice(#$id $budgetId ${kind.name})';
}

final budgetRemovedNoticeProvider =
    NotifierProvider<BudgetRemovedNotices, BudgetRemovedNotice?>(
      BudgetRemovedNotices.new,
      name: 'budgetRemovedNotice',
    );

final class BudgetRemovedNotices extends Notifier<BudgetRemovedNotice?> {
  int _posted = 0;
  int _claimed = 0;

  @override
  BudgetRemovedNotice? build() => null;

  void post({
    required String budgetId,
    required String name,
    required BudgetRemovalKind kind,
  }) {
    if (!ref.mounted) {
      _log.fine(
        'budget removed notice budgetId=$budgetId kind=${kind.name} not '
        'shown: app scope is gone',
      );
      return;
    }
    final notice = BudgetRemovedNotice(
      id: ++_posted,
      budgetId: budgetId,
      name: name,
      kind: kind,
    );
    state = notice;
    _log.fine(
      'budget removed notice posted $notice → snackbar on the main screen',
    );
  }

  bool claim(int id) {
    if (id <= _claimed) return false;
    _claimed = id;
    return true;
  }
}

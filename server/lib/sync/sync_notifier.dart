import 'package:logging/logging.dart';

final _log = Logger('sync');

final class BudgetsChanged {
  BudgetsChanged({
    required this.reason,
    required this.userId,
    required Set<String> budgetIds,
    required this.cursor,
    Set<String> formerMemberIds = const {},
  }) : budgetIds = Set.unmodifiable(budgetIds),
       formerMemberIds = Set.unmodifiable(formerMemberIds);

  final String reason;
  final String userId;
  final Set<String> budgetIds;
  final int cursor;
  final Set<String> formerMemberIds;

  @override
  String toString() =>
      'BudgetsChanged($reason userId=$userId '
      'budgetIds=[${(budgetIds.toList()..sort()).join(',')}] cursor=$cursor'
      '${formerMemberIds.isEmpty ? '' : ' formerMemberIds=[${(formerMemberIds.toList()..sort()).join(',')}]'})';
}

abstract interface class SyncNotifier {
  void budgetsChanged(BudgetsChanged event);
}

final class NoopSyncNotifier implements SyncNotifier {
  const NoopSyncNotifier();

  @override
  void budgetsChanged(BudgetsChanged event) {
    _log.fine('sync change not delivered, no realtime subscribers: $event');
  }
}

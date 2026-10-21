import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/app.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/repositories/budgets_repository.dart';
import 'package:milionchik/features/month/month_header.dart';
import 'package:milionchik/ui/components/avatar.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';

const String _secretName = 'Тайный бюджет Ани';

final class _BrokenBudgets implements BudgetsRepository {
  _BrokenBudgets(this.budget);

  final Budget budget;

  @override
  Stream<List<Budget>> watchAll() => Stream.value([budget]);

  @override
  Stream<Budget?> watchById(String id) => Stream.error(
    SqliteException(
      extendedResultCode: 11,
      message: 'database disk image is malformed',
      causingStatement: 'SELECT * FROM budgets WHERE id = ? AND name = ? AND deleted_at IS NULL',
      parametersToStatement: [id, _secretName],
    ),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  late List<LogRecord> records;
  late StreamSubscription<LogRecord> sub;

  setUp(() {
    records = [];
    Logger.root.level = Level.ALL;
    sub = Logger.root.onRecord.listen(records.add);
  });
  tearDown(() => sub.cancel());

  testWidgets('бюджет не прочитался: warn [month] с типом, кодом, SQL и '
      'стеком, параметры только типами, шапка без плашки, поиск и аватар на '
      'месте', (tester) async {
    final now = DateTime.utc(2026, 10, 19, 9);
    final budget = Budget(
      id: 'budget-broken',
      kind: BudgetKind.personal,
      name: _secretName,
      emoji: '👛',
      ownerId: 'user-me',
      createdAt: now,
      updatedAt: now,
      updatedBy: 'user-me',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(openTestDatabase()),
          budgetsRepositoryProvider.overrideWithValue(_BrokenBudgets(budget)),
        ],
        child: MilionchikApp(today: LocalDate(2026, 10, 19)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MonthHeaderView), findsOneWidget);
    expect(find.text(_secretName), findsNothing);
    expect(find.byType(AppAvatar), findsOneWidget);
    expect(find.bySemanticsLabel('Поиск'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final warnings = [
      for (final r in records)
        if (r.loggerName == 'month' && r.level == Level.WARNING)
          formatLogRecord(r),
    ];
    expect(warnings, hasLength(1));
    final line = warnings.single;
    expect(
      line,
      contains(
        'WARN  [month] header budget budgetId=budget-broken load failed, '
        'showing header without budget: SqliteException',
      ),
    );
    expect(line, contains('database disk image is malformed'));
    expect(line, contains('SELECT * FROM budgets WHERE id = ? AND name = ?'));
    expect(line, contains('<text:13>, <text:${_secretName.length}>'));
    expect(line, contains('stack:'));

    for (final r in records) {
      expect(formatLogRecord(r), isNot(contains(_secretName)));
      expect('${r.error}', isNot(contains(_secretName)));
    }
  });
}

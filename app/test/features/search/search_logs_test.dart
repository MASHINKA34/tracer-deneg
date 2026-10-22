import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/features/search/search_results.dart';
import 'package:milionchik/features/search/search_screen.dart';

import '../../support/app_scope.dart';
import 'search_fixture.dart';

bool _mentions(LogRecord r, String text) =>
    r.message.contains(text) ||
    '${r.error}'.contains(text) ||
    '${r.stackTrace}'.contains(text);

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('каждый поиск — debug [search] с длиной запроса, фильтрами, '
      'числом результатов и мс; текста запроса в логах нет', (tester) async {
    final db = openTestDatabase();
    final seed = (await tester.runAsync(() => seedSearchMockup(db)))!;
    final h = await openSearch(tester, seed: (_) async {}, database: db);

    await typeQuery(tester, 'Кофе');

    final done = [
      for (final r in h.records)
        if (r.loggerName == 'search' &&
            r.level == Level.FINE &&
            r.message.startsWith('search done'))
          r.message,
    ];
    expect(done, [
      matches(
        '^search done trigger=open length=0 amount=false period=all '
        'range=all categories=0 budget=${seed.budgetId} results=11 '
        r'in \d+ms$',
      ),
      matches(
        '^search done trigger=typing length=4 amount=false period=all '
        'range=all categories=0 budget=${seed.budgetId} results=5 '
        r'in \d+ms$',
      ),
    ]);
    expect(h.records.where((r) => _mentions(r, 'Кофе')), isEmpty);
    expect(h.records.where((r) => _mentions(r, 'кофе')), isEmpty);
    expect(
      h.records.where(
        (r) => r.loggerName == 'search' && r.level >= Level.WARNING,
      ),
      isEmpty,
    );
  });

  testWidgets('запрос к базе упал — error [search] с причиной, параметры '
      'запроса скрыты, на экране текст ошибки', (tester) async {
    final h = await openSearch(tester);
    h.records.clear();
    final query = List.filled(6000, 'кофе').join(' ');

    await tester.enterText(find.byType(EditableText), query);
    await tester.pump(searchDebounce);
    await settleSearch(tester);

    final failed = [
      for (final r in h.records)
        if (r.loggerName == 'search' && r.level == Level.SEVERE) r,
    ];
    expect(failed, hasLength(1));
    expect(
      failed.single.message,
      matches(
        '^search failed trigger=typing length=${query.length} amount=false '
        r'period=all range=all categories=0 budget=\S+ after \d+ms, error '
        r'text shown: SqliteException.*LIKE or GLOB pattern too complex',
      ),
    );
    expect('${failed.single.error}', contains('<text:'));
    expect(failed.single.stackTrace, isNotNull);
    expect(h.records.where((r) => _mentions(r, 'кофе')), isEmpty);
    expect(find.byType(SearchFailed), findsOneWidget);
    expect(
      find.text('Не получилось найти траты. Попробуй ещё раз'),
      findsOneWidget,
    );
  });
}

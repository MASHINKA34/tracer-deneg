import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import 'expense_delete_harness.dart';

Future<void> _failUpdates(DeleteHarness h) => h.tester.runAsync(
  () => h.db.customStatement(
    'CREATE TRIGGER expenses_fail BEFORE UPDATE ON expenses '
    "BEGIN SELECT RAISE(ABORT, 'disk I/O error'); END",
  ),
);

void _expectNoSecrets(DeleteHarness h) {
  for (final r in h.records) {
    final text = formatLogRecord(r);
    expect(text, isNot(contains('Пятёрочка')), reason: text);
    if (r.level >= Level.INFO) {
      expect(text, isNot(contains('64000')), reason: text);
      expect(text, isNot(contains('640$nbsp₽')), reason: text);
    }
  }
}

void main() {
  testWidgets('ошибка базы при удалении: строка возвращается на место, '
      'снекбар «Не удалось удалить трату. Попробуй ещё раз» без «Отменить», '
      'error [expense] без параметров SQL, суммы и комментария', (
    tester,
  ) async {
    final h = await DeleteHarness.start(tester);
    await _failUpdates(h);

    await h.swipe(h.todayRow('Пятёрочка · 18:40'));

    expect(h.todayRow('Пятёрочка · 18:40'), findsOneWidget);
    expect(h.inToday(find.text(rub('1 100'))), findsOneWidget);
    expect(
      find.text('Не удалось удалить трату. Попробуй ещё раз'),
      findsOneWidget,
    );
    expect(h.undoButton, findsNothing);
    expect(await h.stored(h.pyaterochka.id), isNotNull);

    final errors = [
      for (final r in h.records)
        if (r.loggerName == 'expense' && r.level == Level.SEVERE) r,
    ];
    expect(errors, hasLength(1));
    expect(
      errors.single.message,
      matches(
        '^expense delete failed id=${h.pyaterochka.id} from=today swipe after '
        r'\d+ms, expense kept, error snackbar: SqliteException',
      ),
    );
    expect(errors.single.message, contains('disk I/O error'));
    expect(errors.single.stackTrace, isNotNull);
    _expectNoSecrets(h);

    await h.wait(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(h.snackbar, findsNothing);
  });

  testWidgets('«Отменить», когда часы уже ушли за 5 с (снекбар ещё не '
      'скрылся): трата остаётся удалённой, снекбар «Не удалось вернуть '
      'трату», info-лог inTime=false', (tester) async {
    final h = await DeleteHarness.start(tester);
    await h.swipe(h.todayRow('Пятёрочка · 18:40'));
    await h.waitSinceDelete(const Duration(seconds: 1));
    h.skew = const Duration(seconds: 6);

    await h.tapUndo();

    expect(h.todayRow('Пятёрочка · 18:40'), findsNothing);
    expect(await h.stored(h.pyaterochka.id), isNull);
    expect(find.text('Не удалось вернуть трату'), findsOneWidget);
    expect(h.undoButton, findsNothing);
    expect(
      h.messages('expense', Level.INFO),
      contains(
        matches(
          '^expense undo id=${h.pyaterochka.id} from=today swipe '
          r'inTime=false after 7\d\d\dms of 5000ms: not restored',
        ),
      ),
    );
    expect(
      h.messages('repo', Level.INFO),
      contains(
        'expense undo delete id=${h.pyaterochka.id} undone=false '
        'reason=window-expired',
      ),
    );
    _expectNoSecrets(h);
  });

  testWidgets('ошибка базы при «Отменить»: трата остаётся удалённой, '
      'снекбар «Не удалось вернуть трату», error [expense] без параметров '
      'SQL', (tester) async {
    final h = await DeleteHarness.start(tester);
    await h.swipe(h.todayRow('Пятёрочка · 18:40'));
    await _failUpdates(h);

    await h.tapUndo();

    expect(h.todayRow('Пятёрочка · 18:40'), findsNothing);
    expect(find.text('Не удалось вернуть трату'), findsOneWidget);
    expect(await h.stored(h.pyaterochka.id), isNull);
    final errors = [
      for (final r in h.records)
        if (r.loggerName == 'expense' && r.level == Level.SEVERE) r,
    ];
    expect(errors, hasLength(1));
    expect(
      errors.single.message,
      matches(
        '^expense undo failed id=${h.pyaterochka.id} from=today swipe '
        r'inTime=true after \d+ms, expense stays deleted, error snackbar: '
        'SqliteException',
      ),
    );
    _expectNoSecrets(h);
  });

  testWidgets('успешные удаление и отмена: в info суммы и комментария нет, '
      'сумма только в debug', (tester) async {
    final h = await DeleteHarness.start(tester);
    await h.swipe(h.todayRow('Пятёрочка · 18:40'));
    await h.tapUndo();

    expect(
      h.messages('expense', Level.FINE),
      contains(
        'expense delete requested id=${h.pyaterochka.id} from=today swipe '
        'kopecks=64000',
      ),
    );
    _expectNoSecrets(h);
  });
}

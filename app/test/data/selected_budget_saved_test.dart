import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/data/budget_selection.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';
import 'package:milionchik/data/session/session.dart';
import 'package:milionchik/data/session/session_providers.dart';
import 'package:milionchik/data/session/session_state.dart';

import 'provider_harness.dart';
import 'sync/pull_fixture.dart';

const _user = SessionUser(
  userId: pullUserId,
  login: 'anya_m',
  displayName: 'Аня',
);

ProviderHarness _signedIn() => ProviderHarness(
  overrides: [
    sessionProvider.overrideWithBuild((ref, _) => const SessionActive(_user)),
  ],
);

Future<void> _seed(ProviderHarness h) => h
    .read(budgetsRepositoryProvider)
    .applyFromServer([serverPersonal(), serverShared()]);

void main() {
  test('выбор общего бюджета пишется в local_prefs и переживает перезапуск: '
      'новый контейнер на той же базе сразу выбирает «Семью»', () async {
    final h = _signedIn();
    await _seed(h);
    final selected = h.watch(selectedBudgetIdProvider);
    expect(await selected.data((id) => id != null), 'budget-personal');

    await h
        .read(budgetSelectionProvider.notifier)
        .select('budget-family', from: 'budget-personal', by: 'test');

    expect(await selected.data((id) => id == 'budget-family'), 'budget-family');
    expect(
      await h
          .read(prefsRepositoryProvider)
          .getString(PrefKeys.selectedBudgetId),
      'budget-family',
    );
    expect(PrefKeys.phoneSettings, isNot(contains(PrefKeys.selectedBudgetId)));

    final restarted = ProviderContainer.test(
      overrides: [
        appDatabaseProvider.overrideWithValue(h.db),
        clockProvider.overrideWithValue(Clock(now: () => fixedNow)),
        sessionProvider.overrideWithBuild(
          (ref, _) => const SessionActive(_user),
        ),
      ],
    );
    final values = <AsyncValue<String?>>[];
    restarted.listen(
      selectedBudgetIdProvider,
      (_, next) => values.add(next),
      fireImmediately: true,
    );
    expect(
      await restarted.read(selectedBudgetIdProvider.future),
      'budget-family',
    );
    await pumpEventQueue();
    expect(
      [
        for (final v in values)
          if (v.hasValue) v.value,
      ],
      ['budget-family'],
    );
    restarted.dispose();

    expect(
      h.lines('budgets', Level.INFO),
      containsAllInOrder([
        endsWith(
          'selected budget budgetId=budget-personal reason=personal '
          'userId=$pullUserId',
        ),
        matches(
          RegExp(
            r'selected budget changed budgetId=budget-family '
            r'from=budget-personal by=test in \d+ms$',
          ),
        ),
        endsWith(
          'selected budget budgetId=budget-family reason=chosen kind=shared '
          'userId=$pullUserId',
        ),
      ]),
    );
  });

  test(
    'выбранный общий бюджет пропал (removedBudgetIds): снова личный, '
    'сохранённый выбор стёрт — вернувшийся бюджет сам не откроется',
    () async {
      final h = _signedIn();
      await _seed(h);
      final selected = h.watch(selectedBudgetIdProvider);
      await h
          .read(budgetSelectionProvider.notifier)
          .select('budget-family', from: null, by: 'test');
      expect(
        await selected.data((id) => id == 'budget-family'),
        'budget-family',
      );

      await h.read(budgetsRepositoryProvider).removeBudgetData([
        'budget-family',
      ]);

      expect(
        await selected.data((id) => id == 'budget-personal'),
        'budget-personal',
      );
      final prefs = h.read(prefsRepositoryProvider);
      await _until(
        () async => await prefs.getString(PrefKeys.selectedBudgetId) == null,
      );

      await h.read(budgetsRepositoryProvider).applyFromServer([serverShared()]);
      await pumpEventQueue();
      expect(selected.last.value, 'budget-personal');
      expect(
        h.lines('budgets', Level.INFO),
        contains(
          endsWith(
            'selected budget budgetId=budget-personal reason=personal '
            'userId=$pullUserId: chosen budgetId=budget-family is gone '
            '(removed or not visible to this user) → stored choice cleared',
          ),
        ),
      );
      expect(
        h.lines('budgets'),
        contains(
          endsWith(
            'stored choice budgetId=budget-family cleared: the budget is gone',
          ),
        ),
      );
    },
  );

  test('сохранён чужой личный бюджет (сделан на телефоне до входа) — он '
      'скрыт, выбран личный вошедшего', () async {
    final h = _signedIn();
    await h.read(budgetsRepositoryProvider).applyFromServer([
      serverPersonal(),
      serverPersonal(id: 'budget-local', ownerId: 'user-local'),
    ]);
    await h
        .read(prefsRepositoryProvider)
        .setString(PrefKeys.selectedBudgetId, 'budget-local');

    final selected = h.watch(selectedBudgetIdProvider);

    expect(await selected.data((id) => id != null), 'budget-personal');
  });

  test('выход стирает выбор бюджета вместе с данными аккаунта', () async {
    final h = _signedIn();
    await _seed(h);
    await h
        .read(budgetSelectionProvider.notifier)
        .select('budget-family', from: null, by: 'test');

    final removal = await h
        .read(accountDataCleanerProvider)
        .clearAccountData('test');

    expect(removal.prefs, contains(PrefKeys.selectedBudgetId));
    expect(
      await h
          .read(prefsRepositoryProvider)
          .getString(PrefKeys.selectedBudgetId),
      isNull,
    );
  });

  test('выбор не сохранился (ошибка базы): ошибка наружу, в логе severe без '
      'параметров запроса, прежний бюджет остаётся', () async {
    final h = _signedIn();
    await _seed(h);
    final selected = h.watch(selectedBudgetIdProvider);
    expect(await selected.data((id) => id != null), 'budget-personal');
    await h.db.customStatement('DROP TABLE local_prefs');

    await expectLater(
      h
          .read(budgetSelectionProvider.notifier)
          .select('budget-family', from: 'budget-personal', by: 'test'),
      throwsA(anything),
    );

    final severe = h.lines('budgets', Level.SEVERE);
    expect(severe, hasLength(1));
    expect(
      severe.single,
      contains(
        'selected budget change failed budgetId=budget-family '
        'from=budget-personal by=test after',
      ),
    );
    expect(severe.single, contains('the previous budget stays open'));
    expect(selected.last.value, 'budget-personal');
  });

  test('combineLatest: первое значение — когда пришли оба потока, дальше — на '
      'каждое изменение любого; ошибка проходит дальше', () async {
    final a = StreamController<String>();
    final b = StreamController<int>();
    final events = <Object>[];
    final sub = combineLatest(
      a.stream,
      b.stream,
      (x, y) => '$x$y',
    ).listen(events.add, onError: (Object e) => events.add('error $e'));

    a.add('a');
    await pumpEventQueue();
    expect(events, isEmpty);
    b.add(1);
    a.add('b');
    b.addError('boom');
    b.add(2);
    await pumpEventQueue();

    expect(events, ['a1', 'b1', 'error boom', 'b2']);
    await sub.cancel();
    expect(a.hasListener, isFalse);
    expect(b.hasListener, isFalse);
  });
}

Future<void> _until(Future<bool> Function() check) async {
  for (var i = 0; i < 100; i++) {
    if (await check()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('condition not met in 1s');
}

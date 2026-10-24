import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/sync/budget_removed_notice.dart';

import '../api/fake_api_adapter.dart';
import 'sync_engine_fixture.dart';

void main() {
  late LogCapture logs;
  late TestClock clock;

  setUp(() {
    logs = LogCapture();
    clock = TestClock(DateTime.utc(2026, 10, 19, 15, 40));
  });

  tearDown(() => logs.dispose());

  Future<(EngineServer, EngineDevice)> memberOfFamily() async {
    final server = seededServer(family: true);
    final phone = EngineDevice(server, name: 'phone', clock: clock);
    addTearDown(phone.dispose);
    await phone.sync();
    expect(await phone.rows('budgets'), 2);
    return (server, phone);
  }

  test('создатель удалил открытый общий бюджет → у участника снекбар '
      '«удалён», а не «исключили»; данные бюджета стёрты', () async {
    final (server, phone) = await memberOfFamily();
    phone.selected = familyBudgetId;
    server.deleteBudget(familyBudgetId);

    await phone.sync();

    expect(phone.notices, hasLength(1));
    final (budget, kind) = phone.notices.single;
    expect((budget.budgetId, budget.deleted), (familyBudgetId, true));
    expect(kind, BudgetRemovalKind.deleted);
    expect(await phone.rows('budgets'), 1);
    expect(
      logs.linesOf('sync', Level.INFO),
      contains(
        endsWith(
          'selected budget removed budgetId=$familyBudgetId kind=shared '
          'as=deleted → personal budget is shown, snackbar notice',
        ),
      ),
    );
  });

  test('исключение участника по-прежнему «исключили»: в deletedBudgetIds '
      'бюджета нет', () async {
    final (server, phone) = await memberOfFamily();
    phone.selected = familyBudgetId;
    server.exclude(familyBudgetId);

    await phone.sync();

    final (budget, kind) = phone.notices.single;
    expect(budget.deleted, isFalse);
    expect(kind, BudgetRemovalKind.excluded);
  });
}

import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/auth_support.dart';
import 'support/budget_support.dart';
import 'support/shared_budget_support.dart';
import 'support/sync_support.dart';
import 'support/test_support.dart';

void main() {
  late LogCapture logs;
  late AuthHarness api;
  late TestUser olga;
  late TestUser boris;
  late TestUser vera;
  late Budget family;

  setUp(() async {
    logs = LogCapture();
    api = await AuthHarness.start();
    olga = await registerTestUser(api, 'olga', displayName: 'Ольга');
    boris = await registerTestUser(api, 'boris', displayName: 'Борис');
    vera = await registerTestUser(api, 'vera', displayName: 'Вера');
    family = await createSharedBudget(api, olga);
    final code = await inviteCodeFor(api, olga, family.id);
    await joinBudget(api, boris, code);
    await joinBudget(api, vera, code);
    logs.clear();
  });

  test('создатель удалил бюджет → у участников и у создателя он и в '
      'removedBudgetIds, и в deletedBudgetIds', () async {
    final cursors = {
      for (final user in [olga, boris, vera])
        user.id: (await pullUntilDone(api, user)).cursor,
    };

    final response = await deleteBudgetRaw(api, olga, family.id);
    expect(response.status, 204, reason: response.text);

    for (final user in [olga, boris, vera]) {
      final pulled = await pullUntilDone(api, user, cursor: cursors[user.id]!);
      expect(pulled.all((p) => p.removedBudgetIds), [family.id]);
      expect(
        pulled.all((p) => p.deletedBudgetIds),
        [family.id],
        reason: user.login,
      );
    }
  });

  test('исключённый и вышедший сам: бюджет только в removedBudgetIds, '
      'deletedBudgetIds пуст; в JSON ключ есть всегда', () async {
    final borisCursor = (await pullUntilDone(api, boris)).cursor;
    final veraCursor = (await pullUntilDone(api, vera)).cursor;

    final removed = await removeMemberRaw(api, olga, family.id, boris.id);
    expect(removed.status, 204, reason: removed.text);
    final left = await leaveRaw(api, vera, family.id);
    expect(left.status, 204, reason: left.text);

    for (final (user, cursor) in [(boris, borisCursor), (vera, veraCursor)]) {
      final pulled = await pullUntilDone(api, user, cursor: cursor);
      expect(pulled.all((p) => p.removedBudgetIds), [family.id]);
      expect(pulled.all((p) => p.deletedBudgetIds), isEmpty, reason: user.login);
    }

    final raw = await api.send(
      'GET',
      '/sync/pull?cursor=0&limit=500',
      bearer: boris.accessToken,
    );
    expect(raw.status, 200, reason: raw.text);
    final json = raw.json;
    expect(json['deletedBudgetIds'], isEmpty);
    expect(json['removedBudgetIds'], [family.id]);
  });
}

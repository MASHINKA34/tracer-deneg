import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'support/auth_support.dart';
import 'support/push_support.dart';
import 'support/shared_budget_support.dart';
import 'support/test_support.dart';

void main() {
  late LogCapture logs;
  late AuthHarness api;
  late TestUser anna;
  late String personal;
  late String category;

  setUp(() async {
    logs = LogCapture();
    api = await AuthHarness.start();
    anna = await registerTestUser(api, 'anna');
    personal = await SharedBudgetFixture(api).personalBudgetOf(anna.id);
    category = await firstCategoryOf(api, personal);
  });

  Expense expense({int kopecks = 64000, String comment = ''}) => expenseRecord(
    budgetId: personal,
    categoryId: category,
    authorId: anna.id,
    kopecks: kopecks,
    comment: comment,
  );

  group('POST /sync/push: пачка целиком', () {
    test('201 изменение — 400 bad_request, ничего не применено; 200 — '
        'принимаются', () async {
      final tooMany = [
        for (var i = 0; i < maxPushBatchSize + 1; i++)
          SyncChange.upsert(expense(kopecks: 100 + i)),
      ];
      final rejected = await pushRaw(
        api,
        anna,
        SyncPushRequest(batchId: newId(), changes: tooMany).toJson(),
      );
      expect(rejected.status, 400);
      expect(rejected.errorCode, ApiErrorCode.badRequest.code);
      expect(
        await api.count(
          r'SELECT count(*)::int FROM expenses WHERE budget_id = $1::uuid',
          [personal],
        ),
        0,
      );
      expect(
        await api.count(
          r'SELECT count(*)::int FROM push_batches WHERE user_id = $1::uuid',
          [anna.id],
        ),
        0,
      );
      expect(
        logs.text,
        contains(
          'push rejected reason=bad_request userId=${anna.id} '
          'problem="too many changes, limit 200"',
        ),
      );

      final full = await pushAs(api, anna, tooMany.sublist(0, 200));
      expect(full.applied, hasLength(200));
      expect(full.rejected, isEmpty);
    });

    test('тело не JSON, нет batchId, changes не список, неверный batchId — '
        '400 bad_request', () async {
      final notJson = await api.send(
        'POST',
        '/sync/push',
        rawBody: '{oops',
        bearer: anna.accessToken,
      );
      expect(notJson.status, 400);
      expect(notJson.errorCode, ApiErrorCode.badRequest.code);

      for (final body in <Object?>[
        {'changes': <Object?>[]},
        {'batchId': newId(), 'changes': 'nope'},
        {
          'batchId': newId(),
          'changes': [
            {'entity': 'wallet', 'op': 'upsert', 'id': newId()},
          ],
        },
        {'batchId': '', 'changes': <Object?>[]},
        {'batchId': 'с пробелом и\nпереводом', 'changes': <Object?>[]},
        {'batchId': 'x' * 65, 'changes': <Object?>[]},
        [1, 2, 3],
      ]) {
        final response = await pushRaw(api, anna, body);
        expect(response.status, 400, reason: '$body');
        expect(response.errorCode, ApiErrorCode.badRequest.code);
      }
      expect(logs.text, isNot(contains('переводом')));
    });

    test('без токена — 401', () async {
      final response = await api.send(
        'POST',
        '/sync/push',
        body: pushBody([]),
      );
      expect(response.status, 401);
    });

    test('пустая пачка — пустой ответ с курсором 0', () async {
      final response = await pushRaw(api, anna, pushBody([]));
      expect(response.status, 200);
      expect(response.headers['cache-control'], 'no-store');
      expect(response.json, {
        'applied': <Object?>[],
        'rejected': <Object?>[],
        'cursor': 0,
      });
    });
  });

  group('POST /sync/push: проверка каждого изменения', () {
    test('нарушения правил shared отклоняются кодами валидации, остальные '
        'изменения пачки применяются', () async {
      final good = expense();
      final empty = expense(kopecks: 0);
      final huge = expense(kopecks: maxExpenseKopecks + 1);
      final longComment = expense(comment: 'к' * (commentMaxLength + 1));
      final nul = expense(comment: 'до\u0000после');
      final badName = categoryRecord(
        budgetId: personal,
        updatedBy: anna.id,
        name: '   ',
      );
      final badEmoji = categoryRecord(
        budgetId: personal,
        updatedBy: anna.id,
        emoji: 'ab',
      );
      final longTitle = recurringRecord(
        budgetId: personal,
        categoryId: category,
        updatedBy: anna.id,
        title: 'т' * (recurringTitleMaxLength + 1),
      );
      final badDay = recurringRecord(
        budgetId: personal,
        categoryId: category,
        updatedBy: anna.id,
        dayOfMonth: 32,
      );
      final response = await pushAs(api, anna, [
        SyncChange.upsert(empty),
        SyncChange.upsert(good),
        SyncChange.upsert(huge),
        SyncChange.upsert(longComment),
        SyncChange.upsert(nul),
        SyncChange.upsert(badName),
        SyncChange.upsert(badEmoji),
        SyncChange.upsert(longTitle),
        SyncChange.upsert(badDay),
      ]);
      expect(response.applied, [good.id]);
      expect(response.rejected, [
        SyncRejection(id: empty.id, code: ValidationError.amountEmpty.code),
        SyncRejection(id: huge.id, code: ValidationError.amountTooLarge.code),
        SyncRejection(
          id: longComment.id,
          code: ValidationError.commentTooLong.code,
        ),
        SyncRejection(id: nul.id, code: ApiErrorCode.validationFailed.code),
        SyncRejection(
          id: badName.id,
          code: ValidationError.categoryNameEmpty.code,
        ),
        SyncRejection(id: badEmoji.id, code: ValidationError.emojiInvalid.code),
        SyncRejection(
          id: longTitle.id,
          code: ValidationError.recurringTitleTooLong.code,
        ),
        SyncRejection(
          id: badDay.id,
          code: ValidationError.dayOfMonthInvalid.code,
        ),
      ]);
      expect(await rowCount(api, 'expenses', good.id), 1);
      for (final id in [empty.id, huge.id, longComment.id, nul.id]) {
        expect(await rowCount(api, 'expenses', id), 0);
      }
      expect(
        logs.text,
        contains(
          'push change rejected reason=comment_too_long entity=expense '
          'op=upsert id=${longComment.id} field=comment',
        ),
      );
      expect(logs.text, isNot(contains('к' * 20)));
    });

    test('сломанные данные — bad_request по изменению, не по пачке', () async {
      final good = expense();
      final wrongId = expense();
      final notUuid = expense();
      final upperCategory = expenseRecord(
        budgetId: personal,
        categoryId: category.toUpperCase(),
        authorId: anna.id,
      );
      final withTombstone = expense();
      final noMonth = expenseRecord(
        budgetId: personal,
        categoryId: category,
        authorId: anna.id,
        recurringId: newId(),
      );
      final changes = <Object?>[
        changeJson(SyncChange.upsert(good)),
        {...changeJson(SyncChange.upsert(wrongId)), 'id': newId()},
        {
          ...changeJson(SyncChange.upsert(notUuid)),
          'id': 'not-a-uuid',
          'data': {...notUuid.toJson(), 'id': 'not-a-uuid'},
        },
        {
          ...changeJson(SyncChange.upsert(good)),
          'id': good.id,
          'data': {...good.toJson(), 'amountKopecks': 'много'},
        },
        changeJson(SyncChange.upsert(upperCategory)),
        {
          ...changeJson(SyncChange.upsert(withTombstone)),
          'data': {
            ...withTombstone.toJson(),
            'deletedAt': encodeInstant(DateTime.now()),
          },
        },
        changeJson(SyncChange.upsert(noMonth)),
      ];
      final response = await pushRaw(api, anna, pushBody(changes));
      expect(response.status, 200);
      final parsed = SyncPushResponse.fromJson(response.json);
      expect(parsed.applied, [good.id]);
      final ids = [for (final c in changes) (c! as Map)['id']];
      expect(parsed.rejected, [
        SyncRejection(id: ids[1]! as String, code: 'bad_request'),
        SyncRejection(id: 'not-a-uuid', code: 'bad_request'),
        SyncRejection(id: good.id, code: 'bad_request'),
        SyncRejection(id: upperCategory.id, code: 'bad_request'),
        SyncRejection(id: withTombstone.id, code: 'bad_request'),
        SyncRejection(id: noMonth.id, code: 'validation_failed'),
      ]);
      expect(await rowCount(api, 'expenses', withTombstone.id), 0);
      expect(await rowCount(api, 'expenses', noMonth.id), 0);
      expect(logs.text, isNot(contains('много')));
    });

    test('updatedAt за пределами 1-9999 годов — validation_failed, '
        'а не 500', () async {
      final ancient = expense();
      final response = await pushRaw(
        api,
        anna,
        pushBody([
          {
            ...changeJson(SyncChange.upsert(ancient)),
            'updatedAt': '-005000-01-01T00:00:00.000Z',
          },
        ]),
      );
      expect(response.status, 200);
      expect(SyncPushResponse.fromJson(response.json).rejected, [
        SyncRejection(id: ancient.id, code: 'validation_failed'),
      ]);
    });
  });
}

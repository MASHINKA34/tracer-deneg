import 'dart:convert';

import 'package:shared/shared.dart';
import 'package:test/test.dart';

Object? _wire(Object? json) => jsonDecode(jsonEncode(json));

void main() {
  test('deletedBudgetIds туда и обратно, ключ в JSON есть всегда', () {
    final response = SyncPullResponse(
      removedBudgetIds: ['b-family', 'b-friends'],
      deletedBudgetIds: ['b-friends'],
      cursor: 90,
      hasMore: false,
    );

    final json = response.toJson();
    expect(json['deletedBudgetIds'], ['b-friends']);
    final parsed = SyncPullResponse.fromJson(_wire(json));
    expect(parsed.removedBudgetIds, ['b-family', 'b-friends']);
    expect(parsed.deletedBudgetIds, ['b-friends']);
    expect(parsed.totalCount, 2);
    expect(
      SyncPullResponse(cursor: 0, hasMore: false).toJson()['deletedBudgetIds'],
      isEmpty,
    );
  });

  test('ответ старого сервера без deletedBudgetIds разбирается, список '
      'пуст', () {
    final parsed = SyncPullResponse.fromJson(
      _wire({
        'budgets': <Object?>[],
        'members': <Object?>[],
        'profiles': <Object?>[],
        'categories': <Object?>[],
        'expenses': <Object?>[],
        'recurring': <Object?>[],
        'removedBudgetIds': ['b-family'],
        'cursor': 5,
        'hasMore': false,
      }),
    );

    expect(parsed.removedBudgetIds, ['b-family']);
    expect(parsed.deletedBudgetIds, isEmpty);
  });

  test('deletedBudgetIds не список строк → FormatException с именем поля', () {
    expect(
      () => SyncPullResponse.fromJson(
        _wire({
          'budgets': <Object?>[],
          'members': <Object?>[],
          'profiles': <Object?>[],
          'categories': <Object?>[],
          'expenses': <Object?>[],
          'recurring': <Object?>[],
          'removedBudgetIds': <Object?>[],
          'deletedBudgetIds': [7],
          'cursor': 5,
          'hasMore': false,
        }),
      ),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('deletedBudgetIds'),
        ),
      ),
    );
  });
}

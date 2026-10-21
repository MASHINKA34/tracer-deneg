import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/core/router.dart';
import 'package:shared/shared.dart';

void main() {
  test('новая трата на день — /expense/new?date=YYYY-MM-DD', () {
    expect(
      AppRoutes.newExpenseOn(LocalDate(2026, 10, 17)),
      '/expense/new?date=2026-10-17',
    );
    expect(
      AppRoutes.newExpenseOn(LocalDate(2026, 1, 5)),
      '/expense/new?date=2026-01-05',
    );
    final uri = Uri.parse(AppRoutes.newExpenseOn(LocalDate(2026, 10, 17)));
    expect(uri.path, AppRoutes.newExpense);
    expect(
      LocalDate.parse(uri.queryParameters[AppRoutes.dateParameter]!),
      LocalDate(2026, 10, 17),
    );
  });

  test('трата — /expense/<id> по шаблону /expense/:id', () {
    const id = '7f3a2c1e-9b8d-4e6f-a5b4-c3d2e1f0a9b8';
    expect(AppRoutes.expenseOf(id), '/expense/$id');
    expect(AppRoutes.expense, '/expense/:id');
    expect(AppRoutes.expenseOf('a b/c'), '/expense/a%20b%2Fc');
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milionchik/features/export/export_rows.dart';
import 'package:milionchik/l10n/app_localizations_ru.dart';
import 'package:shared/shared.dart';

final _l10n = AppLocalizationsRu();
final DateTime _at = DateTime.utc(2026, 10, 1);
final LocalDate _today = LocalDate(2026, 10, 19);

Budget _budget(BudgetKind kind, String name) => Budget(
  id: 'b-${kind.name}',
  kind: kind,
  name: name,
  emoji: '👛',
  ownerId: 'me',
  createdAt: _at,
  updatedAt: _at,
  updatedBy: 'me',
);

Expense _expense(String id, String categoryId, {String author = 'me'}) =>
    Expense(
      id: id,
      budgetId: 'b',
      categoryId: categoryId,
      amount: const Money.rubles(10),
      spentOn: LocalDate(2026, 10, 5),
      authorId: author,
      createdAt: _at,
      updatedAt: _at,
      updatedBy: author,
    );

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  test('бюджет в строке, имени файла и колонке: личный — «Личный», общий — '
      'своё название', () {
    expect(
      exportBudgetName(_l10n, _budget(BudgetKind.personal, 'Личный бюджет')),
      'Личный',
    );
    expect(
      exportBudgetName(_l10n, _budget(BudgetKind.shared, 'Семья и друзья')),
      'Семья и друзья',
    );
    expect(
      csvFileName(
        exportBudgetName(_l10n, _budget(BudgetKind.personal, 'Личный бюджет')),
        MonthPeriod(_today.yearMonth),
      ),
      'milionchik_lichnyj_2026-10.csv',
    );
  });

  test('«Кто добавил»: имя из профиля, свои траты без профиля — «Я», '
      'автора без профиля — «Удалённый участник»', () {
    final profiles = {
      'u2': MemberProfile(
        userId: 'u2',
        displayName: 'Дима',
        avatarColor: CategoryColor.values.first,
      ),
      'me': MemberProfile(
        userId: 'me',
        displayName: 'Маша',
        avatarColor: CategoryColor.values.last,
      ),
    };
    String author(String id, Map<String, MemberProfile> p) =>
        exportAuthorName(_l10n, id, currentUserId: 'me', profiles: p);

    expect(author('u2', profiles), 'Дима');
    expect(author('me', profiles), 'Маша');
    expect(author('me', const {}), 'Я');
    expect(author('u3', profiles), 'Удалённый участник');
  });

  test('категория траты: своя по id; удалённая — системная «Другое» бюджета; '
      'категорий нет — «Другое» из пресета', () {
    var n = 0;
    final categories = buildPresetCategories(
      budgetId: 'b',
      updatedBy: 'me',
      now: _at,
      newId: () => 'c-${n++}',
    );
    final cafe = categories.singleWhere((c) => c.name == 'Кафе');
    final system = categories.singleWhere((c) => c.isSystem);

    final rows = exportRows(
      expenses: [_expense('e1', cafe.id), _expense('e2', 'gone')],
      categories: categories,
      budgetName: 'Личный',
      authorOf: (id) => 'автор $id',
    );
    expect([for (final r in rows) r.category], ['Кафе', system.name]);
    expect([for (final r in rows) r.author], ['автор me', 'автор me']);
    expect([for (final r in rows) r.budget], ['Личный', 'Личный']);

    final orphan = exportRows(
      expenses: [_expense('e3', 'gone')],
      categories: const [],
      budgetName: 'Личный',
      authorOf: (id) => id,
    );
    expect(orphan.single.category, 'Другое');
  });

  test('периоды: месяц и год от сегодня, свои даты как выбраны; подписи '
      'чипов', () {
    final month = exportPeriodOf(ExportPeriodKind.month, _today);
    final year = exportPeriodOf(ExportPeriodKind.year, _today);
    final range = RangePeriod(LocalDate(2026, 9, 1), LocalDate(2026, 9, 30));
    final custom = exportPeriodOf(
      ExportPeriodKind.custom,
      _today,
      custom: range,
    );

    expect(month.fileNamePart, '2026-10');
    expect(
      (month.from, month.to),
      (LocalDate(2026, 10, 1), LocalDate(2026, 10, 31)),
    );
    expect(year.fileNamePart, '2026');
    expect(custom.fileNamePart, '2026-09-01_2026-09-30');
    expect(exportMonthChip(_today), 'Октябрь 2026');
    expect(exportYearChip(_l10n, _today), '2026 год');
    expect(exportCustomChip(_l10n, null), 'Свои даты');
    expect(exportCustomChip(_l10n, range), '01.09.2026 – 30.09.2026');
  });
}

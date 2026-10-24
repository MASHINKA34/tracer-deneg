import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milionchik/data/session/session.dart';
import 'package:milionchik/features/budgets/budget_screen.dart';
import 'package:milionchik/features/budgets/budget_screen_view.dart';
import 'package:milionchik/features/budgets/expense_authors.dart';
import 'package:milionchik/l10n/app_localizations.dart';
import 'package:shared/shared.dart';

final LocalDate _today = LocalDate(2026, 10, 19);

Expense _expense({
  required LocalDate day,
  required DateTime created,
  String comment = '',
  String author = 'user-dima',
}) => Expense(
  id: 'expense-1',
  budgetId: 'budget-family',
  categoryId: 'category-1',
  amount: Money(234000),
  spentOn: day,
  comment: comment,
  authorId: author,
  createdAt: created.toUtc(),
  updatedAt: created.toUtc(),
  updatedBy: author,
);

BudgetMember _member(String userId, MemberRole role, CategoryColor color) =>
    BudgetMember(
      budgetId: 'budget-family',
      userId: userId,
      role: role,
      avatarColor: color,
      joinedAt: DateTime.utc(2026, 10, 2, 6),
    );

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    await initializeDateFormatting('ru');
    l10n = lookupAppLocalizations(const Locale('ru'));
  });

  test('день траты: сегодня с временем записи, вчера без времени, если '
      'записана позже; дальше - число и месяц, другой год - с годом', () {
    expect(
      recentExpenseSubtitle(
        l10n,
        _expense(
          day: _today,
          created: DateTime(2026, 10, 19, 12, 5),
          comment: 'Лента',
        ),
        _today,
      ),
      'Лента · сегодня, 12:05',
    );
    expect(
      recentExpenseSubtitle(
        l10n,
        _expense(
          day: LocalDate(2026, 10, 18),
          created: DateTime(2026, 10, 19, 9),
          comment: 'Коммуналка',
        ),
        _today,
      ),
      'Коммуналка · вчера',
    );
    expect(
      recentExpenseSubtitle(
        l10n,
        _expense(
          day: LocalDate(2026, 10, 18),
          created: DateTime(2026, 10, 18, 21, 30),
        ),
        _today,
      ),
      'вчера, 21:30',
    );
    expect(
      recentExpenseSubtitle(
        l10n,
        _expense(
          day: LocalDate(2026, 10, 17),
          created: DateTime(2026, 10, 18, 8),
          comment: 'Аптека',
        ),
        _today,
      ),
      'Аптека · 17 октября',
    );
    expect(
      recentExpenseSubtitle(
        l10n,
        _expense(
          day: LocalDate(2025, 12, 31),
          created: DateTime(2026, 1, 2, 8),
        ),
        _today,
      ),
      '31 декабря 2025',
    );
  });

  test('участники: создатель первым, порядок остальных по вступлению; имя '
      'себя - из сессии, чужое - из профиля, без профиля - «Участник»', () {
    final anya = _member('user-anya', MemberRole.member, CategoryColor.blue);
    final dima = _member('user-dima', MemberRole.owner, CategoryColor.green);
    final mama = _member('user-mama', MemberRole.member, CategoryColor.pink);
    expect(budgetMembersInOrder([anya, dima, mama]).map((m) => m.userId), [
      'user-dima',
      'user-anya',
      'user-mama',
    ]);
    const user = SessionUser(
      userId: 'user-anya',
      login: 'anya_m',
      displayName: 'Аня',
    );
    const profiles = {
      'user-dima': MemberProfile(
        userId: 'user-dima',
        displayName: 'Дима',
        avatarColor: CategoryColor.green,
      ),
    };
    expect(
      [
        for (final m in [anya, dima, mama])
          budgetMemberName(l10n, m, user: user, profiles: profiles),
      ],
      ['Аня', 'Дима', 'Участник'],
    );
  });

  test('автор траты: буква и цвет участника; вышедший и неизвестный - '
      '«Удалённый участник»', () {
    const user = SessionUser(
      userId: 'user-anya',
      login: 'anya_m',
      displayName: 'Аня',
    );
    final members = [
      _member('user-anya', MemberRole.owner, CategoryColor.blue),
      _member('user-dima', MemberRole.member, CategoryColor.green),
    ];
    const profiles = {
      'user-dima': MemberProfile(
        userId: 'user-dima',
        displayName: 'Дима',
        avatarColor: CategoryColor.orange,
      ),
      'user-gone': MemberProfile(
        userId: 'user-gone',
        displayName: 'Оля',
        avatarColor: CategoryColor.teal,
      ),
    };
    final authors = ExpenseAuthors(
      budgetId: 'budget-family',
      members: members,
      profiles: profiles,
      user: user,
    );
    final dima = expenseRowAuthor(l10n, authors.of('user-dima')!);
    expect(
      (dima.letter, dima.color, dima.name),
      ('Д', CategoryColor.green, 'Дима'),
    );
    final self = expenseRowAuthor(l10n, authors.of('user-anya')!);
    expect((self.letter, self.color), ('А', CategoryColor.blue));
    final gone = expenseRowAuthor(l10n, authors.of('user-gone')!);
    expect((gone.letter, gone.name), ('У', 'Удалённый участник'));
    expect(authors.of('user-unknown'), isA<RemovedAuthor>());
  });

  test('код для TalkBack - по буквам', () {
    expect(spellInviteCode('MLN-48K2'), 'M L N, 4 8 K 2');
  });
}

import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/session/session.dart';
import 'package:milionchik/data/session/session_providers.dart';
import 'package:milionchik/data/session/session_state.dart';
import 'package:milionchik/features/budgets/expense_authors.dart';
import 'package:milionchik/l10n/app_localizations.dart';
import 'package:shared/shared.dart';

import '../../support/app_scope.dart';
import '../profile/profile_fixture.dart';
import 'expense_authors_fixture.dart';

const SessionUser _me = SessionUser(
  userId: 'user-me',
  login: 'anya_m',
  displayName: 'Аня',
);

BudgetMember _member(String userId, CategoryColor color) => BudgetMember(
  budgetId: 'budget-family',
  userId: userId,
  role: MemberRole.member,
  avatarColor: color,
  joinedAt: DateTime.utc(2026, 10, 2, 6),
);

MemberProfile _profile(String userId, String name, CategoryColor color) =>
    MemberProfile(userId: userId, displayName: name, avatarColor: color);

ExpenseAuthors _authors({
  List<BudgetMember>? members,
  Map<String, MemberProfile>? profiles,
  SessionUser? user = _me,
}) => ExpenseAuthors(
  budgetId: 'budget-family',
  members:
      members ??
      [
        _member('user-me', CategoryColor.blue),
        _member('user-dima', CategoryColor.green),
        _member('user-silent', CategoryColor.teal),
      ],
  profiles:
      profiles ??
      {
        'user-dima': _profile('user-dima', 'Дима', CategoryColor.orange),
        'user-left': _profile('user-left', 'Оля', CategoryColor.purple),
        'user-deleted': _profile(
          'user-deleted',
          'Удалённый участник',
          CategoryColor.red,
        ),
      },
  user: user,
);

void main() {
  late AppLocalizations l10n;
  late List<LogRecord> records;
  late StreamSubscription<LogRecord> sub;

  setUpAll(() => l10n = lookupAppLocalizations(const Locale('ru')));

  setUp(() {
    records = [];
    Logger.root.level = Level.ALL;
    sub = Logger.root.onRecord.listen(records.add);
  });

  tearDown(() async {
    await sub.cancel();
    Logger.root.level = Level.INFO;
  });

  Iterable<String> missing() => records
      .where((r) => r.loggerName == 'budgets')
      .map((r) => r.message)
      .where((m) => m.startsWith('author profile missing'));

  test('участник с профилем: имя из профиля, цвет - его цвет в этом '
      'бюджете, буква - первая буква имени', () {
    final dima = _authors().of('user-dima');

    expect(dima, isA<MemberAuthor>());
    final row = expenseRowAuthor(l10n, dima!);
    expect(
      (row.letter, row.color, row.name),
      ('Д', CategoryColor.green, 'Дима'),
    );
    expect(expenseAuthorName(l10n, dima), 'Дима');
  });

  test('своя трата: имя вошедшего, цвет из своей строки участника', () {
    final self = _authors().of('user-me');

    final row = expenseRowAuthor(l10n, self!);
    expect((row.letter, row.color, row.name), ('А', CategoryColor.blue, 'Аня'));
  });

  test('вышел, исключён или удалил аккаунт (нет среди участников) - '
      '«Удалённый участник» с буквой «У», даже если старый профиль с именем '
      'остался на телефоне', () {
    final authors = _authors();

    for (final id in ['user-left', 'user-deleted', 'user-never-seen']) {
      final author = authors.of(id);
      expect(author, isA<RemovedAuthor>(), reason: id);
      expect(expenseAuthorName(l10n, author!), 'Удалённый участник');
      final row = expenseRowAuthor(l10n, author);
      expect((row.letter, row.name), ('У', 'Удалённый участник'));
    }
  });

  test('участник без профиля на телефоне - без аватара и одна строка debug '
      '«author profile missing» с userId, без имён', () {
    final authors = _authors();

    expect(authors.of('user-silent'), isNull);
    expect(authors.of('user-silent'), isNull);
    expect(authors.of('user-never-seen'), isA<RemovedAuthor>());
    expect(authors.of('user-left'), isA<RemovedAuthor>());

    final lines = missing().toList();
    expect(lines, hasLength(2));
    expect(
      lines.first,
      'author profile missing userId=user-silent budgetId=budget-family '
      'members=3 profiles=3: active member → no avatar',
    );
    expect(
      lines.last,
      'author profile missing userId=user-never-seen budgetId=budget-family '
      'members=3 profiles=3: not a member → removed member',
    );
    expect(
      records.where((r) => r.loggerName == 'budgets').map((r) => r.level),
      everyElement(Level.FINE),
    );
    for (final line in lines) {
      expect(line, isNot(contains('Дима')));
      expect(line, isNot(contains('Оля')));
      expect(line, isNot(contains('Аня')));
    }
  });

  test('свою трату без строки участника не подписываем и не пишем в лог', () {
    final authors = _authors(
      members: [_member('user-dima', CategoryColor.green)],
    );

    expect(authors.of('user-me'), isNull);
    expect(missing(), isEmpty);
  });

  test('провайдер: личный бюджет - авторов нет; общий - по участникам и '
      'профилям из базы', () async {
    final db = openTestDatabase();
    await seedAuthors(db, mama: MamaState.left);
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(Clock(now: () => testNow)),
        sessionProvider.overrideWithBuild(
          (ref, _) => const SessionActive(profileUser),
        ),
      ],
    );
    addTearDown(container.dispose);
    final personal = container.listen(
      expenseAuthorsProvider(personalId),
      (_, _) {},
    );
    final family = container.listen(
      expenseAuthorsProvider(familyId),
      (_, _) {},
    );
    for (var i = 0; i < 50 && family.read() == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(personal.read(), isNull);
    final authors = family.read()!;
    expect(
      expenseRowAuthor(l10n, authors.of(dimaId)!).color,
      CategoryColor.green,
    );
    expect(expenseRowAuthor(l10n, authors.of(meId)!).name, 'Аня');
    expect(authors.of(mamaId), isA<RemovedAuthor>());
    personal.close();
    family.close();
  });
}

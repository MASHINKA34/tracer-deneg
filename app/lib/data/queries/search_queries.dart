import 'package:drift/drift.dart';
import 'package:shared/shared.dart';

import '../db/app_database.dart';
import '../db/converters.dart';
import '../repositories/records.dart';
import 'query_runner.dart';

const int recentCommentsLimit = 6;

final class SearchFilters {
  SearchFilters({
    required this.budgetId,
    this.text = '',
    this.from,
    this.to,
    Set<String> categoryIds = const {},
  }) : categoryIds = Set.unmodifiable(categoryIds);

  final String budgetId;
  final String text;
  final LocalDate? from;
  final LocalDate? to;
  final Set<String> categoryIds;

  @override
  bool operator ==(Object other) =>
      other is SearchFilters &&
      other.budgetId == budgetId &&
      other.text == text &&
      other.from == from &&
      other.to == to &&
      other.categoryIds.length == categoryIds.length &&
      other.categoryIds.containsAll(categoryIds);

  @override
  int get hashCode => Object.hash(
    budgetId,
    text,
    from,
    to,
    Object.hashAllUnordered(categoryIds),
  );

  @override
  String toString() =>
      'SearchFilters(budget=$budgetId length=${text.length} '
      'period=${describePeriod(from, to)} categories=${categoryIds.length})';
}

final class SearchResult {
  const SearchResult({
    required this.expenses,
    required this.count,
    required this.total,
  });

  final List<Expense> expenses;
  final int count;
  final Money total;

  @override
  String toString() => 'SearchResult(count=$count, total=$total)';
}

String escapeLikePattern(String text) =>
    text.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');

abstract interface class SearchQueries {
  Stream<SearchResult> watchSearch(SearchFilters filters);

  Stream<List<String>> watchRecentComments(
    String budgetId, {
    int limit = recentCommentsLimit,
  });
}

final class DriftSearchQueries implements SearchQueries {
  DriftSearchQueries(this._db, {Duration slowThreshold = slowQueryThreshold})
    : _runner = QueryRunner(_db, slowThreshold: slowThreshold);

  static const LocalDateConverter _dates = LocalDateConverter();
  static const String _escape = r'\';

  final AppDatabase _db;
  final QueryRunner _runner;

  $ExpensesTable get _e => _db.expenses;

  $CategoriesTable get _c => _db.categories;

  Join<HasResultSet, Object?> _categoryJoin() => leftOuterJoin(
    _c,
    _c.id.equalsExp(_e.categoryId) & _c.deletedAt.isNull(),
    useColumns: false,
  );

  Expression<bool> _amountMatches(AmountQuery amount) {
    final kopecks = _e.amountKopecks.abs();
    final rubles = kopecks / const Constant(100);
    final rublesText = rubles.cast<String>();
    final digits = amount.kopecks;
    if (digits == null) return rublesText.like('${amount.rubles}%');
    final part = kopecks - rubles * const Constant(100);
    return switch (digits.length) {
      0 => rublesText.equals(amount.rubles),
      1 =>
        rublesText.equals(amount.rubles) &
            part.isBetweenValues(
              int.parse(digits) * 10,
              int.parse(digits) * 10 + 9,
            ),
      _ => rublesText.equals(amount.rubles) & part.equals(int.parse(digits)),
    };
  }

  Expression<bool> _matches(SearchFilters f) {
    var where = _e.budgetId.equals(f.budgetId) & _e.deletedAt.isNull();
    final from = f.from;
    final to = f.to;
    if (from != null) {
      where = where & _e.spentOn.isBiggerOrEqualValue(_dates.toSql(from));
    }
    if (to != null) {
      where = where & _e.spentOn.isSmallerOrEqualValue(_dates.toSql(to));
    }
    if (f.categoryIds.isNotEmpty) {
      where = where & _e.categoryId.isIn(f.categoryIds);
    }
    final text = normalizeSearchText(f.text);
    if (text.isEmpty) return where;
    final pattern = '%${escapeLikePattern(text)}%';
    var match =
        _e.commentSearch.like(pattern, escapeChar: _escape) |
        _c.nameSearch.like(pattern, escapeChar: _escape);
    final amount = parseAmountQuery(f.text);
    if (amount != null) match = match | _amountMatches(amount);
    return where & match;
  }

  @override
  Stream<SearchResult> watchSearch(SearchFilters filters) {
    final where = _matches(filters);
    final list = _db.select(_e).join([_categoryJoin()])
      ..where(where)
      ..orderBy([
        OrderingTerm.desc(_e.spentOn),
        OrderingTerm.desc(_e.createdAt),
        OrderingTerm.asc(_e.id),
      ]);
    final count = countAll();
    final total = _e.amountKopecks.sum();
    final summary = _db.selectOnly(_e)
      ..join([_categoryJoin()])
      ..addColumns([count, total])
      ..where(where);
    final text = normalizeSearchText(filters.text);
    return _runner.watch(
      'search',
      'budget=${filters.budgetId} '
          'period=${describePeriod(filters.from, filters.to)} '
          'categories=${filters.categoryIds.length} length=${text.length} '
          'amount=${parseAmountQuery(filters.text) != null}',
      tables: {_e, _c},
      rows: (result) => result.count,
      run: () => _db.transaction(() async {
        final rows = await list.get();
        final totals = await summary.getSingle();
        return SearchResult(
          expenses: [for (final r in rows) expenseFromRow(r.readTable(_e))],
          count: totals.read(count)!,
          total: Money(totals.read(total) ?? 0),
        );
      }),
    );
  }

  @override
  Stream<List<String>> watchRecentComments(
    String budgetId, {
    int limit = recentCommentsLimit,
  }) {
    final lastUsed = _e.createdAt.max();
    final query = _db.selectOnly(_e)
      ..addColumns([_e.comment, lastUsed])
      ..where(
        _e.budgetId.equals(budgetId) &
            _e.deletedAt.isNull() &
            _e.comment.trim().isNotValue(''),
      )
      ..groupBy([_e.comment])
      ..orderBy([OrderingTerm.desc(lastUsed), OrderingTerm.asc(_e.comment)])
      ..limit(limit);
    return _runner.watch(
      'recent-comments',
      'budget=$budgetId limit=$limit',
      tables: {_e},
      rows: (comments) => comments.length,
      run: () async => List.unmodifiable([
        for (final row in await query.get()) row.read(_e.comment)!,
      ]),
    );
  }
}

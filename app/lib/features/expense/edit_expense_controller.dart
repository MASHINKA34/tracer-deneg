import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../core/clock.dart';
import '../../data/db/redact_db_error.dart';
import '../../data/providers.dart';
import '../../data/repositories/repository_errors.dart';

final _log = Logger('expense');

enum ExpenseField { amount, category, date, comment }

final class ExpenseEdits {
  const ExpenseEdits({
    this.amount,
    this.categoryId,
    this.spentOn,
    this.comment,
    this.saving = false,
  });

  final Money? amount;
  final String? categoryId;
  final LocalDate? spentOn;
  final String? comment;
  final bool saving;

  Money amountOf(Expense expense) => amount ?? expense.amount;

  String categoryOf(Expense expense) => categoryId ?? expense.categoryId;

  LocalDate dateOf(Expense expense) => spentOn ?? expense.spentOn;

  String commentOf(Expense expense) => comment ?? expense.comment;

  List<ExpenseField> changedFields(Expense expense) => [
    if (amount != null && amount != expense.amount) ExpenseField.amount,
    if (categoryId != null && categoryId != expense.categoryId)
      ExpenseField.category,
    if (spentOn != null && spentOn != expense.spentOn) ExpenseField.date,
    if (comment != null && comment != expense.comment) ExpenseField.comment,
  ];

  ExpenseEdits copyWith({
    Money? amount,
    String? categoryId,
    LocalDate? spentOn,
    String? comment,
    bool? saving,
  }) => ExpenseEdits(
    amount: amount ?? this.amount,
    categoryId: categoryId ?? this.categoryId,
    spentOn: spentOn ?? this.spentOn,
    comment: comment ?? this.comment,
    saving: saving ?? this.saving,
  );
}

String fieldNames(List<ExpenseField> fields) =>
    fields.isEmpty ? 'none' : fields.map((f) => f.name).join(',');

enum EditExpenseSave { saved, noChanges, busy, missing, failed }

final class EditExpenseController extends Notifier<ExpenseEdits> {
  EditExpenseController(this.expenseId);

  final String expenseId;

  @override
  ExpenseEdits build() => const ExpenseEdits();

  bool setAmount(Money amount) {
    final error = validateAmount(amount);
    if (error != null) {
      _log.warning(
        'expense edit id=$expenseId amount rejected: ${error.code}, keeping '
        'the previous amount',
      );
      return false;
    }
    if (amount == state.amount) {
      _log.fine('expense edit id=$expenseId amount unchanged');
      return false;
    }
    state = state.copyWith(amount: amount);
    _log.fine(
      'expense edit id=$expenseId amount set kopecks=${amount.kopecks}',
    );
    return true;
  }

  bool setCategory(String categoryId) {
    if (categoryId == state.categoryId) {
      _log.fine('expense edit id=$expenseId category $categoryId unchanged');
      return false;
    }
    state = state.copyWith(categoryId: categoryId);
    _log.fine('expense edit id=$expenseId category set category=$categoryId');
    return true;
  }

  bool setDate(LocalDate date, {required String by}) {
    final today = ref.read(clockProvider).today();
    if (date.isAfter(today)) {
      _log.warning(
        'expense edit id=$expenseId date $date by=$by rejected: future day '
        'today=$today, keeping ${state.spentOn ?? 'the saved date'}',
      );
      return false;
    }
    if (date == state.spentOn) {
      _log.fine('expense edit id=$expenseId date $date by=$by unchanged');
      return false;
    }
    final from = state.spentOn;
    state = state.copyWith(spentOn: date);
    _log.fine(
      'expense edit id=$expenseId date ${from ?? 'saved'} → $date by=$by',
    );
    return true;
  }

  bool setComment(String comment) {
    final value = normalizeText(comment);
    final length = textLength(value);
    final error = validateComment(value);
    if (error != null) {
      _log.warning(
        'expense edit id=$expenseId comment rejected: ${error.code} '
        'length=$length max=$commentMaxLength, keeping the previous comment',
      );
      return false;
    }
    if (value == state.comment) {
      _log.fine('expense edit id=$expenseId comment unchanged length=$length');
      return false;
    }
    state = state.copyWith(comment: value);
    _log.fine('expense edit id=$expenseId comment set length=$length');
    return true;
  }

  Future<EditExpenseSave> save(Expense original) async {
    final edits = state;
    if (edits.saving) {
      _log.fine(
        'expense edit id=$expenseId save ignored: previous save is in '
        'progress',
      );
      return EditExpenseSave.busy;
    }
    final changed = edits.changedFields(original);
    final names = fieldNames(changed);
    if (changed.isEmpty) {
      _log.fine('expense edit id=$expenseId save ignored: nothing changed');
      return EditExpenseSave.noChanges;
    }
    state = edits.copyWith(saving: true);
    final sw = Stopwatch()..start();
    try {
      final updated = await ref
          .read(expensesRepositoryProvider)
          .update(
            expenseId,
            amount: changed.contains(ExpenseField.amount) ? edits.amount : null,
            categoryId: changed.contains(ExpenseField.category)
                ? edits.categoryId
                : null,
            spentOn: changed.contains(ExpenseField.date) ? edits.spentOn : null,
            comment: changed.contains(ExpenseField.comment)
                ? edits.comment
                : null,
          );
      _log.info(
        'expense updated id=$expenseId budgetId=${updated.budgetId} '
        'fields=$names in ${sw.elapsedMilliseconds}ms',
      );
      _log.fine(
        'expense updated id=$expenseId amountKopecks=${updated.amount.kopecks} '
        'category=${updated.categoryId} date=${updated.spentOn}',
      );
      if (ref.mounted) state = const ExpenseEdits();
      return EditExpenseSave.saved;
    } on RepositoryException catch (e, st) {
      if (e.failure == RepositoryFailure.notFound) {
        _log.warning(
          'expense update failed id=$expenseId fields=$names after '
          '${sw.elapsedMilliseconds}ms: expense is deleted or missing, '
          'nothing saved',
        );
        if (ref.mounted) state = state.copyWith(saving: false);
        return EditExpenseSave.missing;
      }
      _log.severe(
        'expense update rejected id=$expenseId fields=$names after '
        '${sw.elapsedMilliseconds}ms, nothing saved: ${e.code}',
        e,
        st,
      );
      if (ref.mounted) state = state.copyWith(saving: false);
      return EditExpenseSave.failed;
    } catch (e, st) {
      var cause = e;
      while (cause is ProviderException) {
        cause = cause.exception;
      }
      final redacted = redactDbError(cause);
      _log.severe(
        'expense update failed id=$expenseId fields=$names after '
        '${sw.elapsedMilliseconds}ms, nothing saved: '
        '${describeError(redacted)}',
        redacted,
        st,
      );
      if (ref.mounted) state = state.copyWith(saving: false);
      return EditExpenseSave.failed;
    }
  }
}

final editExpenseControllerProvider = NotifierProvider.autoDispose
    .family<EditExpenseController, ExpenseEdits, String>(
      EditExpenseController.new,
      name: 'editExpenseController',
    );

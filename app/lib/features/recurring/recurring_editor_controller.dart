import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../core/clock.dart';
import '../../data/db/redact_db_error.dart';
import '../../data/providers.dart';
import '../../data/recurring_service.dart';
import '../../data/repositories/repository_errors.dart';

final _log = Logger('recurring');

enum RecurringField { title, amount, category, day }

String recurringFieldNames(List<RecurringField> fields) =>
    fields.isEmpty ? 'none' : fields.map((f) => f.name).join(',');

LocalDate firstChargeOfNewRule(int dayOfMonth, LocalDate today) =>
    chargeDate(dayOfMonth, startMonthForNewRule(dayOfMonth, today));

YearMonth? startMonthAfterDayChange(
  RecurringRule rule,
  int dayOfMonth,
  LocalDate today,
) {
  if (dayOfMonth == rule.dayOfMonth) return null;
  if (rule.startMonth < YearMonth.of(today)) return null;
  final due = dueMonths(
    startMonth: rule.startMonth,
    dayOfMonth: rule.dayOfMonth,
    today: today,
  );
  if (due.isNotEmpty) return null;
  final start = startMonthForNewRule(dayOfMonth, today);
  return start == rule.startMonth ? null : start;
}

final class RecurringDraft {
  const RecurringDraft({
    this.title,
    this.amount,
    this.categoryId,
    this.day,
    this.submitted = false,
    this.busy = false,
  });

  final String? title;
  final Money? amount;
  final String? categoryId;
  final int? day;
  final bool submitted;
  final bool busy;

  String titleOf(RecurringRule? original) => title ?? original?.title ?? '';

  Money amountOf(RecurringRule? original) =>
      amount ?? original?.amount ?? Money.zero;

  String? categoryOf(RecurringRule? original) =>
      categoryId ?? original?.categoryId;

  int dayOf(RecurringRule? original, LocalDate today) =>
      day ?? original?.dayOfMonth ?? today.day;

  List<RecurringField> changedFields(RecurringRule original) => [
    if (title != null && normalizeText(title!) != original.title)
      RecurringField.title,
    if (amount != null && amount != original.amount) RecurringField.amount,
    if (categoryId != null && categoryId != original.categoryId)
      RecurringField.category,
    if (day != null && day != original.dayOfMonth) RecurringField.day,
  ];

  ValidationError? titleError(RecurringRule? original) =>
      validateRecurringTitle(titleOf(original));

  ValidationError? amountError(RecurringRule? original) =>
      validateAmount(amountOf(original));

  bool categoryMissing(RecurringRule? original) => categoryOf(original) == null;

  List<String> errorCodes(RecurringRule? original) => [
    ?titleError(original)?.code,
    ?amountError(original)?.code,
    if (categoryMissing(original)) 'category_missing',
  ];

  ValidationError? visibleTitleError(RecurringRule? original) {
    final error = titleError(original);
    if (error == ValidationError.recurringTitleEmpty &&
        title == null &&
        !submitted) {
      return null;
    }
    return error;
  }

  ValidationError? visibleAmountError(RecurringRule? original) =>
      submitted ? amountError(original) : null;

  bool visibleCategoryMissing(RecurringRule? original) =>
      submitted && categoryMissing(original);

  RecurringDraft copyWith({
    String? title,
    Money? amount,
    String? categoryId,
    int? day,
    bool? submitted,
    bool? busy,
  }) => RecurringDraft(
    title: title ?? this.title,
    amount: amount ?? this.amount,
    categoryId: categoryId ?? this.categoryId,
    day: day ?? this.day,
    submitted: submitted ?? this.submitted,
    busy: busy ?? this.busy,
  );
}

enum RecurringSave { saved, invalid, noChanges, busy, missing, failed }

enum RecurringDelete { deleted, busy, missing, failed }

final class RecurringEditorController extends Notifier<RecurringDraft> {
  RecurringEditorController(this.ruleId);

  final String? ruleId;

  String get _target => ruleId == null ? 'new' : 'id=$ruleId';

  @override
  RecurringDraft build() => const RecurringDraft();

  void setTitle(String text) {
    if (text == state.title) return;
    state = state.copyWith(title: text);
    _log.fine(
      'recurring edit $_target title changed length=${textLength(text)} '
      'error=${validateRecurringTitle(text)?.code ?? 'none'}',
    );
  }

  bool setAmount(Money amount) {
    final error = validateAmount(amount);
    if (error != null) {
      _log.warning(
        'recurring edit $_target amount rejected: ${error.code}, keeping the '
        'previous amount',
      );
      return false;
    }
    if (amount == state.amount) {
      _log.fine('recurring edit $_target amount unchanged');
      return false;
    }
    state = state.copyWith(amount: amount);
    _log.fine('recurring edit $_target amount set kopecks=${amount.kopecks}');
    return true;
  }

  bool setCategory(String categoryId) {
    if (categoryId == state.categoryId) {
      _log.fine('recurring edit $_target category=$categoryId unchanged');
      return false;
    }
    final from = state.categoryId;
    state = state.copyWith(categoryId: categoryId);
    _log.fine(
      'recurring edit $_target category '
      '${from ?? (ruleId == null ? 'none' : 'saved')} → $categoryId',
    );
    return true;
  }

  bool setDay(int day) {
    final error = validateDayOfMonth(day);
    if (error != null) {
      _log.warning(
        'recurring edit $_target day=$day rejected: ${error.code}, keeping '
        'the previous day',
      );
      return false;
    }
    if (day == state.day) {
      _log.fine('recurring edit $_target day=$day unchanged');
      return false;
    }
    final from = state.day;
    state = state.copyWith(day: day);
    _log.fine(
      'recurring edit $_target day '
      '${from ?? (ruleId == null ? 'today' : 'saved')} → $day',
    );
    return true;
  }

  Future<RecurringSave> save(
    RecurringRule? original, {
    String? budgetId,
  }) async {
    final draft = state;
    if (draft.busy) {
      _log.fine(
        'recurring save $_target ignored: previous save or delete is in '
        'progress',
      );
      return RecurringSave.busy;
    }
    if (ruleId != null && original == null) {
      _log.warning(
        'recurring save $_target ignored: rule is not loaded, deleted or '
        'missing',
      );
      return RecurringSave.missing;
    }
    final errors = draft.errorCodes(original);
    if (errors.isNotEmpty) {
      state = draft.copyWith(submitted: true);
      _log.info(
        'recurring save $_target blocked: ${errors.join(',')} '
        'titleLength=${textLength(normalizeText(draft.titleOf(original)))} '
        'max=$recurringTitleMaxLength, errors shown on the form',
      );
      return RecurringSave.invalid;
    }
    final changed = original == null
        ? RecurringField.values
        : draft.changedFields(original);
    if (changed.isEmpty) {
      _log.fine(
        'recurring save $_target: nothing changed → back without writing',
      );
      return RecurringSave.noChanges;
    }
    final names = recurringFieldNames(changed);
    final today = ref.read(clockProvider).today();
    state = draft.copyWith(busy: true);
    final sw = Stopwatch()..start();
    final repo = ref.read(recurringRepositoryProvider);
    try {
      if (original == null) {
        final targetBudget = budgetId;
        if (targetBudget == null) {
          _log.warning(
            'recurring create ignored: no budget selected, nothing saved',
          );
          if (ref.mounted) state = state.copyWith(busy: false);
          return RecurringSave.missing;
        }
        final day = draft.dayOf(null, today);
        final start = startMonthForNewRule(day, today);
        final created = await repo.create(
          budgetId: targetBudget,
          categoryId: draft.categoryOf(null)!,
          title: draft.titleOf(null),
          amount: draft.amountOf(null),
          dayOfMonth: day,
          startMonth: start,
        );
        _log.info(
          'recurring rule created id=${created.id} '
          'budgetId=${created.budgetId} day=${created.dayOfMonth} '
          'from=${created.startMonth} firstCharge=${chargeDate(day, start)} '
          'today=$today in ${sw.elapsedMilliseconds}ms',
        );
      } else {
        final day = changed.contains(RecurringField.day) ? draft.day : null;
        final start = day == null
            ? null
            : startMonthAfterDayChange(original, day, today);
        final updated = await repo.update(
          original.id,
          title: changed.contains(RecurringField.title) ? draft.title : null,
          amount: changed.contains(RecurringField.amount) ? draft.amount : null,
          categoryId: changed.contains(RecurringField.category)
              ? draft.categoryId
              : null,
          dayOfMonth: day,
          startMonth: start,
        );
        _log.info(
          'recurring rule updated id=${updated.id} '
          'budgetId=${updated.budgetId} fields=$names '
          'day=${updated.dayOfMonth} from=${updated.startMonth}'
          '${start == null ? '' : ' (was ${original.startMonth}: no charge '
                    'was due yet, start recounted as for a new rule)'} '
          'in ${sw.elapsedMilliseconds}ms, created expenses unchanged',
        );
      }
      final saved = sw.elapsedMilliseconds;
      final run = await ref
          .read(recurringServiceProvider)
          .run(RecurringRunReason.ruleSaved);
      if (run.ok) {
        _log.fine(
          'recurring save $_target: generator after save created='
          '${run.created} skipped=${run.skipped} in '
          '${sw.elapsedMilliseconds - saved}ms',
        );
      } else {
        _log.warning(
          'recurring save $_target: rule is saved but the generator after '
          'save failed (failedRules=${run.failedRules} '
          'error=${run.error == null ? '-' : describeError(run.error!)}), '
          'due expenses will be created on the next run',
        );
      }
      if (ref.mounted) state = const RecurringDraft();
      return RecurringSave.saved;
    } on RepositoryException catch (e, st) {
      if (ref.mounted) state = state.copyWith(busy: false);
      if (e.failure == RepositoryFailure.notFound) {
        _log.warning(
          'recurring save failed $_target fields=$names after '
          '${sw.elapsedMilliseconds}ms: rule is deleted or missing, nothing '
          'saved',
        );
        return RecurringSave.missing;
      }
      _log.severe(
        'recurring save rejected $_target fields=$names after '
        '${sw.elapsedMilliseconds}ms, nothing saved: ${e.code}',
        e,
        st,
      );
      return RecurringSave.failed;
    } catch (e, st) {
      final redacted = redactDbError(_unwrap(e));
      _log.severe(
        'recurring save failed $_target fields=$names after '
        '${sw.elapsedMilliseconds}ms, nothing saved: '
        '${describeError(redacted)}',
        redacted,
        st,
      );
      if (ref.mounted) state = state.copyWith(busy: false);
      return RecurringSave.failed;
    }
  }

  Future<RecurringDelete> delete(RecurringRule rule) async {
    if (state.busy) {
      _log.fine(
        'recurring delete id=${rule.id} ignored: previous save or delete is '
        'in progress',
      );
      return RecurringDelete.busy;
    }
    state = state.copyWith(busy: true);
    final sw = Stopwatch()..start();
    try {
      await ref.read(recurringRepositoryProvider).delete(rule.id);
      _log.info(
        'recurring rule deleted id=${rule.id} budgetId=${rule.budgetId} '
        'day=${rule.dayOfMonth} from=${rule.startMonth} '
        'in ${sw.elapsedMilliseconds}ms, created expenses stay, no new ones',
      );
      return RecurringDelete.deleted;
    } on RepositoryException catch (e, st) {
      if (ref.mounted) state = state.copyWith(busy: false);
      if (e.failure == RepositoryFailure.notFound) {
        _log.warning(
          'recurring delete failed id=${rule.id} after '
          '${sw.elapsedMilliseconds}ms: rule is already deleted or missing',
        );
        return RecurringDelete.missing;
      }
      _log.severe(
        'recurring delete failed id=${rule.id} budgetId=${rule.budgetId} '
        'after ${sw.elapsedMilliseconds}ms, nothing deleted: ${e.code}',
        e,
        st,
      );
      return RecurringDelete.failed;
    } catch (e, st) {
      final redacted = redactDbError(_unwrap(e));
      _log.severe(
        'recurring delete failed id=${rule.id} budgetId=${rule.budgetId} '
        'after ${sw.elapsedMilliseconds}ms, nothing deleted: '
        '${describeError(redacted)}',
        redacted,
        st,
      );
      if (ref.mounted) state = state.copyWith(busy: false);
      return RecurringDelete.failed;
    }
  }
}

Object _unwrap(Object error) {
  var cause = error;
  while (cause is ProviderException) {
    cause = cause.exception;
  }
  return cause;
}

final recurringEditorControllerProvider = NotifierProvider.autoDispose
    .family<RecurringEditorController, RecurringDraft, String?>(
      RecurringEditorController.new,
      name: 'recurringEditorController',
    );

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../../data/db/redact_db_error.dart';
import '../../data/providers.dart';
import '../../data/repositories/repository_errors.dart';

final _log = Logger('categories');

const List<String> frequentCategoryEmojis = [
  '☕',
  '🍔',
  '🍕',
  '🍣',
  '🥐',
  '🍺',
  '🛒',
  '🚕',
  '🏠',
  '💊',
  '👕',
  '🎮',
  '🎁',
  '📱',
  '🏋️',
  '✈️',
  '🐾',
  '📚',
  '💇',
];

const String otherEmojiTile = '➕';

const String defaultCategoryEmoji = '☕';

const CategoryColor defaultCategoryColor = CategoryColor.green;

enum CategoryField { name, emoji, color }

String categoryFieldNames(List<CategoryField> fields) =>
    fields.isEmpty ? 'none' : fields.map((f) => f.name).join(',');

final class CategoryDraft {
  const CategoryDraft({
    this.name,
    this.emoji,
    this.color,
    this.submitted = false,
    this.busy = false,
  });

  final String? name;
  final String? emoji;
  final CategoryColor? color;
  final bool submitted;
  final bool busy;

  String nameOf(Category? original) => name ?? original?.name ?? '';

  String emojiOf(Category? original) =>
      emoji ?? original?.emoji ?? defaultCategoryEmoji;

  CategoryColor colorOf(Category? original) =>
      color ?? original?.color ?? defaultCategoryColor;

  List<CategoryField> changedFields(Category original) => [
    if (name != null && normalizeText(name!) != original.name)
      CategoryField.name,
    if (emoji != null && emoji != original.emoji) CategoryField.emoji,
    if (color != null && color != original.color) CategoryField.color,
  ];

  ValidationError? nameError(Category? original) =>
      validateCategoryName(nameOf(original));

  ValidationError? visibleNameError(Category? original) {
    final error = nameError(original);
    if (error == ValidationError.categoryNameEmpty &&
        name == null &&
        !submitted) {
      return null;
    }
    return error;
  }

  CategoryDraft copyWith({
    String? name,
    String? emoji,
    CategoryColor? color,
    bool? submitted,
    bool? busy,
  }) => CategoryDraft(
    name: name ?? this.name,
    emoji: emoji ?? this.emoji,
    color: color ?? this.color,
    submitted: submitted ?? this.submitted,
    busy: busy ?? this.busy,
  );
}

enum CategorySave { saved, invalid, noChanges, busy, missing, system, failed }

enum CategoryDelete { deleted, busy, missing, system, failed }

final class CategoryEditorController extends Notifier<CategoryDraft> {
  CategoryEditorController(this.categoryId);

  final String? categoryId;

  String get _target => categoryId == null ? 'new' : 'id=$categoryId';

  @override
  CategoryDraft build() => const CategoryDraft();

  void setName(String text) {
    if (text == state.name) return;
    state = state.copyWith(name: text);
    _log.fine(
      'category edit $_target name changed length=${textLength(text)} '
      'error=${validateCategoryName(text)?.code ?? 'none'}',
    );
  }

  bool setEmoji(String emoji, {required String from}) {
    final value = normalizeText(emoji);
    final error = validateEmoji(value);
    if (error != null) {
      _log.warning(
        'category edit $_target emoji from=$from rejected: ${error.code} '
        'length=${textLength(value)}, keeping the previous emoji',
      );
      return false;
    }
    if (value == state.emoji) {
      _log.fine('category edit $_target emoji from=$from unchanged');
      return false;
    }
    state = state.copyWith(emoji: value);
    _log.fine('category edit $_target emoji set from=$from');
    return true;
  }

  bool setColor(CategoryColor color) {
    if (color == state.color) {
      _log.fine('category edit $_target color ${color.name} unchanged');
      return false;
    }
    final from = state.color;
    state = state.copyWith(color: color);
    _log.fine(
      'category edit $_target color '
      '${from?.name ?? (categoryId == null ? 'default' : 'saved')} → '
      '${color.name}',
    );
    return true;
  }

  Future<CategorySave> save(Category? original, {String? budgetId}) async {
    final draft = state;
    if (draft.busy) {
      _log.fine(
        'category save $_target ignored: previous save or delete is in '
        'progress',
      );
      return CategorySave.busy;
    }
    final creating = categoryId == null;
    if (!creating && original == null) {
      _log.warning(
        'category save $_target ignored: category is not loaded, deleted '
        'or missing',
      );
      return CategorySave.missing;
    }
    if (original != null && original.isSystem) {
      _log.warning(
        'category save $_target rejected: system category cannot be edited',
      );
      return CategorySave.system;
    }
    final nameError = draft.nameError(original);
    if (nameError != null) {
      state = draft.copyWith(submitted: true);
      _log.info(
        'category save $_target blocked: ${nameError.code} '
        'length=${textLength(normalizeText(draft.nameOf(original)))} '
        'max=$categoryNameMaxLength, error shown under the name field',
      );
      return CategorySave.invalid;
    }
    final changed = original == null
        ? CategoryField.values
        : draft.changedFields(original);
    if (changed.isEmpty) {
      _log.fine(
        'category save $_target: nothing changed → back without writing',
      );
      return CategorySave.noChanges;
    }
    final names = categoryFieldNames(changed);
    state = draft.copyWith(busy: true);
    final sw = Stopwatch()..start();
    final repo = ref.read(categoriesRepositoryProvider);
    try {
      if (original == null) {
        final targetBudget = budgetId;
        if (targetBudget == null) {
          _log.warning(
            'category create ignored: no budget selected, nothing saved',
          );
          if (ref.mounted) state = state.copyWith(busy: false);
          return CategorySave.missing;
        }
        final created = await repo.create(
          budgetId: targetBudget,
          name: draft.nameOf(null),
          emoji: draft.emojiOf(null),
          color: draft.colorOf(null),
        );
        _log.info(
          'category created id=${created.id} budgetId=${created.budgetId} '
          'order=${created.sortOrder} color=${created.color?.name} '
          'in ${sw.elapsedMilliseconds}ms',
        );
      } else {
        final updated = await repo.update(
          original.id,
          name: changed.contains(CategoryField.name) ? draft.name : null,
          emoji: changed.contains(CategoryField.emoji) ? draft.emoji : null,
          color: changed.contains(CategoryField.color) ? draft.color : null,
        );
        _log.info(
          'category updated id=${updated.id} budgetId=${updated.budgetId} '
          'fields=$names in ${sw.elapsedMilliseconds}ms',
        );
      }
      if (ref.mounted) state = const CategoryDraft();
      return CategorySave.saved;
    } on RepositoryException catch (e, st) {
      if (ref.mounted) state = state.copyWith(busy: false);
      switch (e.failure) {
        case RepositoryFailure.notFound:
          _log.warning(
            'category save failed $_target fields=$names after '
            '${sw.elapsedMilliseconds}ms: category is deleted or missing, '
            'nothing saved',
          );
          return CategorySave.missing;
        case RepositoryFailure.systemCategory:
          _log.warning(
            'category save rejected $_target fields=$names after '
            '${sw.elapsedMilliseconds}ms: system category, nothing saved',
          );
          return CategorySave.system;
        case RepositoryFailure.validation ||
            RepositoryFailure.otherCategoryMissing:
          _log.severe(
            'category save rejected $_target fields=$names after '
            '${sw.elapsedMilliseconds}ms, nothing saved: ${e.code}',
            e,
            st,
          );
          return CategorySave.failed;
      }
    } catch (e, st) {
      final redacted = redactDbError(_unwrap(e));
      _log.severe(
        'category save failed $_target fields=$names after '
        '${sw.elapsedMilliseconds}ms, nothing saved: '
        '${describeError(redacted)}',
        redacted,
        st,
      );
      if (ref.mounted) state = state.copyWith(busy: false);
      return CategorySave.failed;
    }
  }

  Future<int?> expenseCount(Category category) async {
    final sw = Stopwatch()..start();
    try {
      final count = await ref
          .read(categoryQueriesProvider)
          .countExpenses(category.id);
      _log.fine(
        'category delete id=${category.id} budgetId=${category.budgetId} '
        'expenses=$count to move in ${sw.elapsedMilliseconds}ms',
      );
      return count;
    } catch (e, st) {
      final redacted = redactDbError(_unwrap(e));
      _log.severe(
        'category delete id=${category.id} budgetId=${category.budgetId}: '
        'counting expenses failed after ${sw.elapsedMilliseconds}ms, delete '
        'dialog not shown: ${describeError(redacted)}',
        redacted,
        st,
      );
      return null;
    }
  }

  Future<CategoryDelete> delete(
    Category category, {
    required int shownExpenses,
  }) async {
    if (state.busy) {
      _log.fine(
        'category delete id=${category.id} ignored: previous save or delete '
        'is in progress',
      );
      return CategoryDelete.busy;
    }
    if (category.isSystem) {
      _log.warning(
        'category delete id=${category.id} rejected: system category cannot '
        'be deleted',
      );
      return CategoryDelete.system;
    }
    state = state.copyWith(busy: true);
    final sw = Stopwatch()..start();
    try {
      final result = await ref
          .read(categoriesRepositoryProvider)
          .delete(category.id);
      _log.info(
        'category deleted id=${category.id} '
        'budgetId=${category.budgetId} '
        'movedExpenses=${result.movedExpenses} '
        'movedRecurring=${result.movedRecurring} shown=$shownExpenses '
        'other=${result.otherCategoryId} in ${sw.elapsedMilliseconds}ms',
      );
      if (result.movedExpenses != shownExpenses) {
        _log.warning(
          'category deleted id=${category.id}: dialog showed '
          '$shownExpenses expenses but ${result.movedExpenses} were moved '
          '(changed while the dialog was open)',
        );
      }
      return CategoryDelete.deleted;
    } on RepositoryException catch (e, st) {
      if (ref.mounted) state = state.copyWith(busy: false);
      switch (e.failure) {
        case RepositoryFailure.notFound:
          _log.warning(
            'category delete failed id=${category.id} after '
            '${sw.elapsedMilliseconds}ms: category is already deleted or '
            'missing',
          );
          return CategoryDelete.missing;
        case RepositoryFailure.systemCategory:
          _log.warning(
            'category delete rejected id=${category.id} after '
            '${sw.elapsedMilliseconds}ms: system category',
          );
          return CategoryDelete.system;
        case RepositoryFailure.validation ||
            RepositoryFailure.otherCategoryMissing:
          _log.severe(
            'category delete failed id=${category.id} '
            'budgetId=${category.budgetId} after '
            '${sw.elapsedMilliseconds}ms, nothing deleted: ${e.code}',
            e,
            st,
          );
          return CategoryDelete.failed;
      }
    } catch (e, st) {
      final redacted = redactDbError(_unwrap(e));
      _log.severe(
        'category delete failed id=${category.id} '
        'budgetId=${category.budgetId} after ${sw.elapsedMilliseconds}ms, '
        'nothing deleted: ${describeError(redacted)}',
        redacted,
        st,
      );
      if (ref.mounted) state = state.copyWith(busy: false);
      return CategoryDelete.failed;
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

final categoryEditorControllerProvider = NotifierProvider.autoDispose
    .family<CategoryEditorController, CategoryDraft, String?>(
      CategoryEditorController.new,
      name: 'categoryEditorController',
    );

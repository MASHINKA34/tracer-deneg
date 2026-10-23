import 'package:drift/drift.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import '../db/app_database.dart';
import '../db/redact_db_error.dart';
import 'prefs_repository.dart';

final _log = Logger('repo');

final class AccountDataRemoval {
  const AccountDataRemoval({
    required this.budgets,
    required this.members,
    required this.profiles,
    required this.categories,
    required this.expenses,
    required this.recurring,
    required this.outbox,
    required this.prefs,
    required this.keptPrefs,
  });

  final int budgets;
  final int members;
  final int profiles;
  final int categories;
  final int expenses;
  final int recurring;
  final int outbox;
  final List<String> prefs;
  final List<String> keptPrefs;

  int get total =>
      budgets +
      members +
      profiles +
      categories +
      expenses +
      recurring +
      outbox +
      prefs.length;

  @override
  String toString() =>
      'budgets=$budgets members=$members profiles=$profiles '
      'categories=$categories expenses=$expenses recurring=$recurring '
      'outbox=$outbox syncState=reset '
      'prefs=[${prefs.join(',')}] keptPrefs=[${keptPrefs.join(',')}]';
}

abstract interface class AccountDataCleaner {
  Future<AccountDataRemoval> clearAccountData(String reason);
}

final class DriftAccountDataCleaner implements AccountDataCleaner {
  DriftAccountDataCleaner(this._db, {Set<String>? keptPrefs})
    : _kept = keptPrefs ?? PrefKeys.phoneSettings;

  final AppDatabase _db;
  final Set<String> _kept;

  @override
  Future<AccountDataRemoval> clearAccountData(String reason) async {
    final sw = Stopwatch()..start();
    _log.fine(
      'account data clear started reason=$reason '
      'keeping phone settings ${_kept.join(',')}',
    );
    try {
      final removal = await _db.transaction(() async {
        final outbox = await _db.delete(_db.outbox).go();
        final expenses = await _db.delete(_db.expenses).go();
        final recurring = await _db.delete(_db.recurringRules).go();
        final categories = await _db.delete(_db.categories).go();
        final members = await _db.delete(_db.budgetMembers).go();
        final profiles = await _db.delete(_db.memberProfiles).go();
        final budgets = await _db.delete(_db.budgets).go();
        await _resetSyncState();
        final keys =
            await (_db.selectOnly(_db.localPrefs)
                  ..addColumns([_db.localPrefs.key]))
                .map((row) => row.read(_db.localPrefs.key)!)
                .get();
        final dropped = [
          for (final key in keys)
            if (!_kept.contains(key)) key,
        ]..sort();
        final kept = [
          for (final key in keys)
            if (_kept.contains(key)) key,
        ]..sort();
        if (dropped.isNotEmpty) {
          await (_db.delete(
            _db.localPrefs,
          )..where((p) => p.key.isIn(dropped))).go();
        }
        return AccountDataRemoval(
          budgets: budgets,
          members: members,
          profiles: profiles,
          categories: categories,
          expenses: expenses,
          recurring: recurring,
          outbox: outbox,
          prefs: dropped,
          keptPrefs: kept,
        );
      });
      _log.info(
        'account data cleared reason=$reason $removal '
        'in ${sw.elapsedMilliseconds}ms',
      );
      return removal;
    } catch (e, st) {
      final error = redactDbError(e);
      _log.severe(
        'account data clear failed reason=$reason '
        'after ${sw.elapsedMilliseconds}ms, transaction rolled back, '
        'nothing removed: ${describeError(error)}',
        error,
        st,
      );
      rethrow;
    }
  }

  Future<void> _resetSyncState() async {
    const values = SyncStatesCompanion(
      cursor: Value(0),
      lastSyncAt: Value(null),
      lastError: Value(null),
    );
    final updated = await (_db.update(
      _db.syncStates,
    )..where((s) => s.id.equals(0))).write(values);
    if (updated == 0) {
      _log.warning(
        'sync_state row id=0 was missing during account data clear → '
        'created with cursor=0',
      );
      await _db
          .into(_db.syncStates)
          .insert(values.copyWith(id: const Value(0)));
    }
  }
}

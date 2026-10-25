import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart' as pg;
import 'package:shared/shared.dart';

import '../auth/auth_service.dart';
import '../auth/password_hasher.dart';
import '../budgets/budget_service.dart';
import '../db/database.dart';

final _log = Logger('account');

const String deletedMemberName = 'Удалённый участник';

const String _userColumns =
    'id, login, display_name, birthday_month, birthday_day, '
    'holidays_enabled, holidays_disabled, created_at, seq';

class ProfileUpdate {
  const ProfileUpdate({
    this.displayName,
    this.birthday = keep,
    this.holidaysEnabled,
    this.holidaysDisabled,
  });

  final String? displayName;
  final Object? birthday;
  final bool? holidaysEnabled;
  final Set<String>? holidaysDisabled;

  List<String> get fields => [
    if (displayName != null) 'displayName',
    if (!identical(birthday, keep)) 'birthday',
    if (holidaysEnabled != null) 'holidaysEnabled',
    if (holidaysDisabled != null) 'holidaysDisabled',
  ];
}

class ProfileChange {
  const ProfileChange({
    required this.user,
    required this.changed,
    required this.seqBefore,
    required this.seqAfter,
  });

  final User user;
  final List<String> changed;
  final int seqBefore;
  final int seqAfter;
}

class AccountDeletion {
  const AccountDeletion({
    required this.personalBudgetsDeleted,
    required this.sharedBudgetsDeleted,
    required this.sharedBudgetsTransferred,
    required this.sharedBudgetsLeft,
    required this.sharedExpensesKept,
    required this.invitesRevoked,
    required this.sessionsDeleted,
  });

  final int personalBudgetsDeleted;
  final int sharedBudgetsDeleted;
  final int sharedBudgetsTransferred;
  final int sharedBudgetsLeft;
  final int sharedExpensesKept;
  final int invitesRevoked;
  final int sessionsDeleted;
}

enum _SharedExit { left, transferred, deleted }

class AccountService {
  AccountService({required this.db, required this.hasher});

  final Database db;
  final PasswordHasher hasher;

  Future<User> me(String userId) async {
    final sw = Stopwatch()..start();
    final rows = await db.execute(
      'SELECT $_userColumns FROM users '
      r'WHERE id = $1::uuid AND deleted_at IS NULL',
      parameters: [userId],
      what: 'read profile',
      logParams: {'userId': userId},
    );
    if (rows.isEmpty) {
      _log.warning(
        'profile read rejected reason=${AuthFailureReason.userDeleted.code} '
        'userId=$userId in ${sw.elapsedMilliseconds}ms',
      );
      throw AuthFailure(AuthFailureReason.userDeleted);
    }
    final user = _userFromRow(rows.first);
    _log.info(
      'profile read userId=$userId seq=${rows.first[8]} '
      'in ${sw.elapsedMilliseconds}ms',
    );
    return user;
  }

  Future<ProfileChange> updateProfile(
    String userId,
    ProfileUpdate update,
  ) async {
    final sw = Stopwatch()..start();
    final requested = update.fields;
    final change = await db.transaction('update profile', (tx) async {
      final rows = await tx.execute(
        'SELECT $_userColumns FROM users '
        r'WHERE id = $1::uuid AND deleted_at IS NULL FOR UPDATE',
        parameters: [userId],
        what: 'lock user for profile update',
        logParams: {'userId': userId},
      );
      if (rows.isEmpty) return null;
      final before = _userFromRow(rows.first);
      final seqBefore = rows.first[8]! as int;
      final displayName = update.displayName;
      final after = before.copyWith(
        displayName: displayName == null ? null : normalizeText(displayName),
        birthday: update.birthday,
        holidaysEnabled: update.holidaysEnabled,
        holidaysDisabled: update.holidaysDisabled,
      );
      final changed = _changedFields(before, after);
      if (changed.isEmpty) {
        return ProfileChange(
          user: after,
          changed: changed,
          seqBefore: seqBefore,
          seqAfter: seqBefore,
        );
      }
      final updated = await tx.execute(
        r'UPDATE users SET display_name = $2, birthday_month = $3::int, '
        r'birthday_day = $4::int, holidays_enabled = $5, '
        r'holidays_disabled = $6 WHERE id = $1::uuid RETURNING seq',
        parameters: [
          userId,
          after.displayName,
          after.birthday?.month,
          after.birthday?.day,
          after.holidaysEnabled,
          pg.TypedValue(
            pg.Type.textArray,
            after.holidaysDisabled.toList()..sort(),
          ),
        ],
        what: 'update profile',
        logParams: {'userId': userId, 'fields': changed.join(',')},
      );
      return ProfileChange(
        user: after,
        changed: changed,
        seqBefore: seqBefore,
        seqAfter: updated.first.first! as int,
      );
    });

    if (change == null) {
      _log.warning(
        'profile update rejected reason=${AuthFailureReason.userDeleted.code} '
        'userId=$userId requested=${requested.join(',')} '
        'in ${sw.elapsedMilliseconds}ms',
      );
      throw AuthFailure(AuthFailureReason.userDeleted);
    }
    if (change.changed.isEmpty) {
      _log.info(
        'profile update without changes userId=$userId '
        'requested=${requested.isEmpty ? '-' : requested.join(',')} '
        'seq=${change.seqBefore} in ${sw.elapsedMilliseconds}ms',
      );
    } else {
      _log.info(
        'profile updated userId=$userId changed=${change.changed.join(',')} '
        'seq=${change.seqBefore}→${change.seqAfter}'
        '${change.seqAfter == change.seqBefore ? ' (profile unchanged)' : ''} '
        'in ${sw.elapsedMilliseconds}ms',
      );
    }
    return change;
  }

  Future<String> loginOf(String userId) async {
    final rows = await db.execute(
      r'SELECT login FROM users WHERE id = $1::uuid AND deleted_at IS NULL',
      parameters: [userId],
      what: 'find login for password attempts',
      logParams: {'userId': userId},
    );
    if (rows.isEmpty) {
      _log.warning(
        'login lookup rejected reason=${AuthFailureReason.userDeleted.code} '
        'userId=$userId',
      );
      throw AuthFailure(AuthFailureReason.userDeleted);
    }
    return rows.first.first! as String;
  }

  Future<AccountDeletion> deleteAccount({
    required String userId,
    required String sessionId,
    required String password,
  }) async {
    final sw = Stopwatch()..start();
    final origin = {'sessionId': sessionId};
    final rows = await db.execute(
      r'SELECT password_hash FROM users '
      r'WHERE id = $1::uuid AND deleted_at IS NULL',
      parameters: [userId],
      what: 'find password hash for account deletion',
      logParams: {'userId': userId},
    );
    if (rows.isEmpty) {
      _rejectDeletion(sw, AuthFailureReason.userDeleted, userId, origin);
    }
    final storedPasswordHash = rows.first.first! as String;
    final matches = await hasher.verify(
      password,
      storedPasswordHash,
      purpose: 'password',
    );
    if (!matches) {
      _rejectDeletion(
        sw,
        AuthFailureReason.badCredentials,
        userId,
        origin,
        cause: 'password_mismatch',
      );
    }
    return _deleteVerified(
      sw,
      userId: userId,
      storedPasswordHash: storedPasswordHash,
      origin: origin,
    );
  }

  Future<AccountDeletion> deleteAccountByLogin({
    required String login,
    required String password,
  }) async {
    final sw = Stopwatch()..start();
    final normalized = normalizeLogin(login);
    final masked = maskLogin(normalized);
    final origin = {'via': 'web', 'login': masked};
    final rows = await db.execute(
      r'SELECT id, password_hash FROM users '
      r'WHERE lower(login) = $1 AND deleted_at IS NULL',
      parameters: [normalized],
      what: 'find user by login for account deletion',
      logParams: {'login': masked},
    );
    if (rows.isEmpty) {
      await hasher.verifyDummy(password, purpose: 'password');
      _rejectDeletion(
        sw,
        AuthFailureReason.badCredentials,
        null,
        origin,
        cause: 'user_not_found',
      );
    }
    final userId = rows.first[0]! as String;
    final storedPasswordHash = rows.first[1]! as String;
    final matches = await hasher.verify(
      password,
      storedPasswordHash,
      purpose: 'password',
    );
    if (!matches) {
      _rejectDeletion(
        sw,
        AuthFailureReason.badCredentials,
        userId,
        origin,
        cause: 'password_mismatch',
      );
    }
    return _deleteVerified(
      sw,
      userId: userId,
      storedPasswordHash: storedPasswordHash,
      origin: origin,
    );
  }

  Future<AccountDeletion> _deleteVerified(
    Stopwatch sw, {
    required String userId,
    required String storedPasswordHash,
    required Map<String, Object?> origin,
  }) async {
    final steps = <String>[];
    final deletion = await db.transaction('delete account', (tx) async {
      steps.clear();
      final locked = await tx.execute(
        r'SELECT 1 FROM users WHERE id = $1::uuid AND deleted_at IS NULL '
        r'AND password_hash = $2 FOR UPDATE',
        parameters: [userId, storedPasswordHash],
        what: 'lock user for account deletion',
        logParams: {'userId': userId},
      );
      if (locked.isEmpty) return null;

      final personal = await tx.execute(
        r'DELETE FROM budgets '
        r"WHERE owner_id = $1::uuid AND kind = 'personal' RETURNING id",
        parameters: [userId],
        what: 'delete personal budget with its data',
        logParams: {'userId': userId},
      );
      for (final row in personal) {
        steps.add('personal budget deleted budgetId=${row[0]} userId=$userId');
      }

      final invites = await tx.execute(
        r'UPDATE invites SET revoked_at = now() '
        r'WHERE created_by = $1::uuid AND revoked_at IS NULL',
        parameters: [userId],
        what: 'revoke invites created by user',
        logParams: {'userId': userId},
      );
      final memberships = await tx.execute(
        r'SELECT b.id, (b.owner_id = m.user_id OR m.role = $2) '
        r'FROM budget_members m JOIN budgets b ON b.id = m.budget_id '
        r'WHERE m.user_id = $1::uuid AND m.left_at IS NULL '
        r"AND b.kind = 'shared' AND b.deleted_at IS NULL "
        r'ORDER BY b.id FOR UPDATE OF b',
        parameters: [userId, MemberRole.owner.name],
        what: 'lock shared budgets of user',
        logParams: {'userId': userId},
      );
      var deleted = 0;
      var transferred = 0;
      var left = 0;
      for (final row in memberships) {
        final exit = await _leaveSharedBudget(
          tx,
          budgetId: row[0]! as String,
          userId: userId,
          isOwner: row[1]! as bool,
          steps: steps,
        );
        switch (exit) {
          case _SharedExit.deleted:
            deleted++;
          case _SharedExit.transferred:
            transferred++;
          case _SharedExit.left:
            left++;
        }
      }

      final kept = await tx.execute(
        r'SELECT count(*)::int FROM expenses e '
        r'JOIN budgets b ON b.id = e.budget_id '
        r"WHERE e.author_id = $1::uuid AND b.kind = 'shared' "
        r'AND b.deleted_at IS NULL AND e.deleted_at IS NULL',
        parameters: [userId],
        what: 'count expenses kept in shared budgets',
        logParams: {'userId': userId},
      );
      await tx.execute(
        r'UPDATE users SET deleted_at = now(), display_name = $2, '
        r'birthday_month = NULL, birthday_day = NULL, '
        r"password_hash = '', recovery_hash = '' WHERE id = $1::uuid",
        parameters: [userId, deletedMemberName],
        what: 'mark user deleted and clear profile',
        logParams: {'userId': userId},
      );
      final sessions = await tx.execute(
        r'DELETE FROM sessions WHERE user_id = $1::uuid',
        parameters: [userId],
        what: 'delete all sessions of deleted user with device names',
        logParams: {'userId': userId},
      );
      return AccountDeletion(
        personalBudgetsDeleted: personal.length,
        sharedBudgetsDeleted: deleted,
        sharedBudgetsTransferred: transferred,
        sharedBudgetsLeft: left,
        sharedExpensesKept: kept.first.first! as int,
        invitesRevoked: invites.affectedRows,
        sessionsDeleted: sessions.affectedRows,
      );
    });

    if (deletion == null) {
      final state = await db.execute(
        r'SELECT deleted_at IS NOT NULL FROM users WHERE id = $1::uuid',
        parameters: [userId],
        what: 'check user after failed deletion lock',
        logParams: {'userId': userId},
      );
      final alreadyDeleted = state.isEmpty || state.first.first == true;
      _rejectDeletion(
        sw,
        alreadyDeleted
            ? AuthFailureReason.userDeleted
            : AuthFailureReason.badCredentials,
        userId,
        origin,
        cause: alreadyDeleted
            ? 'deleted_concurrently'
            : 'password_changed_concurrently',
      );
    }

    for (final step in steps) {
      _log.info('account deletion: $step');
    }
    final budgetsDeleted =
        deletion.personalBudgetsDeleted + deletion.sharedBudgetsDeleted;
    _log.info(
      'account deleted userId=$userId ${formatContext(origin)} '
      'budgetsDeleted=$budgetsDeleted '
      '(personal=${deletion.personalBudgetsDeleted} '
      'shared=${deletion.sharedBudgetsDeleted}) '
      'budgetsTransferred=${deletion.sharedBudgetsTransferred} '
      'budgetsLeft=${deletion.sharedBudgetsLeft} '
      'sharedExpensesKept=${deletion.sharedExpensesKept} '
      'invitesRevoked=${deletion.invitesRevoked} '
      'sessionsDeleted=${deletion.sessionsDeleted} '
      'in ${sw.elapsedMilliseconds}ms',
    );
    return deletion;
  }

  Future<_SharedExit> _leaveSharedBudget(
    DbSession tx, {
    required String budgetId,
    required String userId,
    required bool isOwner,
    required List<String> steps,
  }) async {
    final context = {'budgetId': budgetId, 'userId': userId};
    final heirs = await tx.execute(
      r'SELECT user_id FROM budget_members '
      r'WHERE budget_id = $1::uuid AND user_id <> $2::uuid '
      r'AND left_at IS NULL ORDER BY joined_at, user_id LIMIT 1',
      parameters: [budgetId, userId],
      what: 'find earliest remaining member',
      logParams: context,
    );

    if (heirs.isEmpty) {
      await tx.execute(
        r'UPDATE budgets SET deleted_at = now(), updated_at = now(), '
        r'updated_by = $2::uuid WHERE id = $1::uuid',
        parameters: [budgetId, userId],
        what: 'tombstone shared budget',
        logParams: context,
      );
      final erased = await eraseBudgetContent(tx, budgetId, context);
      await tx.execute(
        r'UPDATE budget_members SET left_at = now() '
        r'WHERE budget_id = $1::uuid AND user_id = $2::uuid',
        parameters: [budgetId, userId],
        what: 'leave shared budget',
        logParams: context,
      );
      await tx.execute(
        r'UPDATE invites SET revoked_at = now() '
        r'WHERE budget_id = $1::uuid AND revoked_at IS NULL',
        parameters: [budgetId],
        what: 'revoke invites of deleted shared budget',
        logParams: {'budgetId': budgetId},
      );
      steps.add(
        'shared budget deleted, no members left '
        'budgetId=$budgetId userId=$userId '
        'erased categories=${erased.categories} '
        'expenses=${erased.expenses} recurring=${erased.recurring}',
      );
      return _SharedExit.deleted;
    }

    if (!isOwner) {
      await tx.execute(
        r'UPDATE budget_members SET left_at = now() '
        r'WHERE budget_id = $1::uuid AND user_id = $2::uuid',
        parameters: [budgetId, userId],
        what: 'leave shared budget',
        logParams: context,
      );
      steps.add(
        'left shared budget budgetId=$budgetId '
        'userId=$userId role=${MemberRole.member.name}',
      );
      return _SharedExit.left;
    }

    final heirId = heirs.first.first! as String;
    final transferContext = {...context, 'heirId': heirId};
    await tx.execute(
      r'UPDATE budget_members SET role = $3 '
      r'WHERE budget_id = $1::uuid AND user_id = $2::uuid',
      parameters: [budgetId, heirId, MemberRole.owner.name],
      what: 'make earliest member owner',
      logParams: transferContext,
    );
    await tx.execute(
      r'UPDATE budget_members SET role = $3, left_at = now() '
      r'WHERE budget_id = $1::uuid AND user_id = $2::uuid',
      parameters: [budgetId, userId, MemberRole.member.name],
      what: 'leave shared budget as former owner',
      logParams: transferContext,
    );
    await tx.execute(
      r'UPDATE budgets SET owner_id = $2::uuid, updated_at = now(), '
      r'updated_by = $3::uuid WHERE id = $1::uuid',
      parameters: [budgetId, heirId, userId],
      what: 'transfer shared budget ownership',
      logParams: transferContext,
    );
    steps.add(
      'shared budget ownership transferred '
      'budgetId=$budgetId userId=$userId newOwnerId=$heirId',
    );
    return _SharedExit.transferred;
  }

  Never _rejectDeletion(
    Stopwatch sw,
    AuthFailureReason reason,
    String? userId,
    Map<String, Object?> origin, {
    String? cause,
  }) {
    _log.warning(
      'account deletion rejected reason=${reason.code} '
      '${formatContext({'userId': userId, ...origin, 'cause': cause})} '
      'in ${sw.elapsedMilliseconds}ms',
    );
    throw AuthFailure(reason);
  }
}

List<String> _changedFields(User before, User after) => [
  if (before.displayName != after.displayName) 'displayName',
  if (before.birthday != after.birthday) 'birthday',
  if (before.holidaysEnabled != after.holidaysEnabled) 'holidaysEnabled',
  if (before.holidaysDisabled.length != after.holidaysDisabled.length ||
      !before.holidaysDisabled.containsAll(after.holidaysDisabled))
    'holidaysDisabled',
];

User _userFromRow(pg.ResultRow row) => User(
  id: row[0]! as String,
  login: row[1]! as String,
  displayName: row[2]! as String,
  birthday: MonthDay.fromParts(row[3] as int?, row[4] as int?),
  holidaysEnabled: row[5]! as bool,
  holidaysDisabled: (row[6]! as List<Object?>).cast<String>().toSet(),
  createdAt: row[7]! as DateTime,
);

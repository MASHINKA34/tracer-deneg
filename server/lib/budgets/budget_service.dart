import 'dart:convert';
import 'dart:math';

import 'package:cryptography/dart.dart' show DartSha256;
import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart' as pg;
import 'package:shared/shared.dart';

import '../db/database.dart';

final _log = Logger('budgets');

const Duration inviteTtl = Duration(hours: 24);

const int inviteCodeAttempts = 5;

const String _budgetColumns =
    'id, kind, name, emoji, owner_id, created_at, updated_at, updated_by, '
    'deleted_at, seq';

enum BudgetFailureReason {
  notFound,
  forbidden,
  personalBudget,
  inviteNotFound,
  memberNotFound,
  removeSelf,
  idTaken,
}

final class BudgetFailure implements Exception {
  const BudgetFailure(this.reason, this.problem);

  final BudgetFailureReason reason;
  final String problem;

  @override
  String toString() => 'BudgetFailure(${reason.name}: $problem)';
}

final class CreatedBudget {
  const CreatedBudget({required this.budget, required this.replayed});

  final Budget budget;
  final bool replayed;
}

final class IssuedInvite {
  const IssuedInvite({required this.code, required this.expiresAt});

  final String code;
  final DateTime expiresAt;
}

enum JoinResult { joined, rejoined, alreadyMember }

final class JoinedBudget {
  const JoinedBudget({required this.budget, required this.result});

  final Budget budget;
  final JoinResult result;
}

enum LeaveResult { left, transferred, deleted }

String hashInviteCode(String normalizedCode) {
  final digest = const DartSha256().hashSync(utf8.encode(normalizedCode)).bytes;
  final buffer = StringBuffer();
  for (final byte in digest) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

final class _Outcome<T> {
  const _Outcome.ok(T this.value) : reason = null, problem = null;

  const _Outcome.rejected(BudgetFailureReason this.reason, String this.problem)
    : value = null;

  final T? value;
  final BudgetFailureReason? reason;
  final String? problem;
}

final class _Access {
  const _Access({
    required this.exists,
    required this.deleted,
    required this.kind,
    required this.role,
  });

  final bool exists;
  final bool deleted;
  final BudgetKind? kind;
  final MemberRole? role;
}

typedef _Tombstones = ({
  int categories,
  int expenses,
  int recurring,
  int invites,
});

class BudgetService {
  BudgetService({required this.db, this._now = DateTime.now, Random? random})
    : _random = random ?? Random.secure();

  final Database db;
  final DateTime Function() _now;
  final Random _random;

  Future<CreatedBudget> create({
    required String userId,
    required String budgetId,
    required String name,
    required String emoji,
  }) async {
    const action = 'create';
    final sw = Stopwatch()..start();
    final context = {'budgetId': budgetId, 'userId': userId};
    final now = normalizeInstant(_now());
    final categories = buildPresetCategories(
      budgetId: budgetId,
      updatedBy: userId,
      now: now,
      newId: newId,
    );
    final color = CategoryColor.values.first;
    final outcome = await _run<CreatedBudget>(action, context, sw, (tx) async {
      final inserted = await tx.execute(
        'INSERT INTO budgets (id, kind, name, emoji, owner_id, created_at, '
        r"updated_at, updated_by) VALUES ($1::uuid, 'shared', $2, $3, "
        r'$4::uuid, $5::timestamptz, $5::timestamptz, $4::uuid) '
        'ON CONFLICT (id) DO NOTHING RETURNING $_budgetColumns',
        parameters: [
          budgetId,
          normalizeText(name),
          normalizeText(emoji),
          userId,
          now,
        ],
        what: 'insert shared budget',
        logParams: context,
      );
      if (inserted.isEmpty) return _replayCreate(tx, budgetId, userId);
      await tx.execute(
        r'INSERT INTO budget_members (budget_id, user_id, role, avatar_color, '
        r'joined_at) VALUES ($1::uuid, $2::uuid, $3, $4, $5::timestamptz)',
        parameters: [budgetId, userId, MemberRole.owner.name, color.name, now],
        what: 'insert shared budget owner',
        logParams: {...context, 'avatarColor': color.name},
      );
      for (final category in categories) {
        await tx.execute(
          r'INSERT INTO categories (id, budget_id, name, emoji, color, '
          r'sort_order, is_system, updated_at, updated_by) VALUES ($1::uuid, '
          r'$2::uuid, $3, $4, $5, $6, $7, $8::timestamptz, $9::uuid)',
          parameters: [
            category.id,
            budgetId,
            category.name,
            category.emoji,
            category.color?.name,
            category.sortOrder,
            category.isSystem,
            now,
            userId,
          ],
          what: 'insert preset category',
          logParams: {
            'budgetId': budgetId,
            'categoryId': category.id,
            'sortOrder': category.sortOrder,
          },
        );
      }
      return _Outcome.ok(
        CreatedBudget(budget: _budgetFromRow(inserted.single), replayed: false),
      );
    });
    final created = _unwrap(action, outcome, context, sw);
    if (created.replayed) {
      _log.info(
        'budget $action replayed: already created by this user, '
        'nothing written budgetId=$budgetId userId=$userId '
        'seq=${created.budget.seq} in ${sw.elapsedMilliseconds}ms',
      );
    } else {
      _log.info(
        'budget $action ok budgetId=$budgetId userId=$userId kind=shared '
        'role=${MemberRole.owner.name} avatarColor=${color.name} '
        'categories=${categories.length} seq=${created.budget.seq} '
        'in ${sw.elapsedMilliseconds}ms',
      );
    }
    return created;
  }

  Future<_Outcome<CreatedBudget>> _replayCreate(
    DbSession tx,
    String budgetId,
    String userId,
  ) async {
    final context = {'budgetId': budgetId, 'userId': userId};
    final rows = await tx.execute(
      'SELECT $_budgetColumns FROM budgets WHERE id = \$1::uuid FOR UPDATE',
      parameters: [budgetId],
      what: 'lock budget with taken id',
      logParams: context,
    );
    if (rows.isEmpty) {
      return const _Outcome.rejected(
        BudgetFailureReason.idTaken,
        'budget id was taken and released concurrently',
      );
    }
    final budget = _budgetFromRow(rows.single);
    final member = await tx.execute(
      r'SELECT role FROM budget_members WHERE budget_id = $1::uuid '
      r'AND user_id = $2::uuid AND left_at IS NULL',
      parameters: [budgetId, userId],
      what: 'membership of user in budget with taken id',
      logParams: context,
    );
    final isOwner =
        member.isNotEmpty && member.single[0] == MemberRole.owner.name;
    if (budget.kind == BudgetKind.shared &&
        budget.ownerId == userId &&
        !budget.isDeleted &&
        isOwner) {
      _log.fine(
        'budget id already taken by the same owner, treating as retry '
        '${formatContext(context)} seq=${budget.seq}',
      );
      return _Outcome.ok(CreatedBudget(budget: budget, replayed: true));
    }
    return _Outcome.rejected(
      BudgetFailureReason.idTaken,
      'id belongs to another budget kind=${budget.kind.name} '
      'sameOwner=${budget.ownerId == userId} deleted=${budget.isDeleted} '
      'activeOwner=$isOwner',
    );
  }

  Future<IssuedInvite> createInvite({
    required String userId,
    required String budgetId,
  }) async {
    const action = 'invite';
    final sw = Stopwatch()..start();
    final context = {'budgetId': budgetId, 'userId': userId};
    _checkBudgetId(action, budgetId, context, sw);
    final now = normalizeInstant(_now());
    final expiresAt = now.add(inviteTtl);
    final outcome = await _run<_Invite>(action, context, sw, (tx) async {
      final access = await _lockBudget(tx, budgetId, userId, action);
      final denied = _denied<_Invite>(access, ownerOnly: true);
      if (denied != null) return denied;
      for (var attempt = 1; attempt <= inviteCodeAttempts; attempt++) {
        final code = normalizeInviteCode(generateInviteCode(_random))!;
        final hash = hashInviteCode(code);
        final inserted = await tx.execute(
          'INSERT INTO invites (code_hash, budget_id, created_by, created_at, '
          r'expires_at) VALUES ($1, $2::uuid, $3::uuid, $4::timestamptz, '
          r'$5::timestamptz) ON CONFLICT (code_hash) DO UPDATE SET '
          'budget_id = EXCLUDED.budget_id, created_by = EXCLUDED.created_by, '
          'created_at = EXCLUDED.created_at, '
          'expires_at = EXCLUDED.expires_at, revoked_at = NULL '
          'WHERE invites.revoked_at IS NOT NULL '
          'OR invites.expires_at <= EXCLUDED.created_at '
          'RETURNING budget_id',
          parameters: [hash, budgetId, userId, now, expiresAt],
          what: 'insert invite code hash',
          logParams: {
            ...context,
            'code': maskInviteCode(code),
            'attempt': '$attempt/$inviteCodeAttempts',
          },
        );
        if (inserted.isEmpty) {
          _log.fine(
            'invite code collides with an active invite, generating another '
            '${formatContext(context)} '
            'attempt=$attempt/$inviteCodeAttempts',
          );
          continue;
        }
        final revoked = await tx.execute(
          r'UPDATE invites SET revoked_at = $3::timestamptz '
          r'WHERE budget_id = $1::uuid AND code_hash <> $2 '
          'AND revoked_at IS NULL',
          parameters: [budgetId, hash, now],
          what: 'revoke previous invites of budget',
          logParams: context,
        );
        return _Outcome.ok((
          code: code,
          attempts: attempt,
          revoked: revoked.affectedRows,
        ));
      }
      throw StateError(
        'invite for budget $budgetId: every one of $inviteCodeAttempts '
        'generated codes collides with an active invite',
      );
    });
    final issued = _unwrap(action, outcome, context, sw);
    _log.info(
      'budget $action ok budgetId=$budgetId userId=$userId '
      'code=${maskInviteCode(issued.code)} '
      'expiresAt=${encodeInstant(expiresAt)} '
      'previousRevoked=${issued.revoked} attempts=${issued.attempts} '
      'in ${sw.elapsedMilliseconds}ms',
    );
    return IssuedInvite(code: issued.code, expiresAt: expiresAt);
  }

  Future<JoinedBudget> join({
    required String userId,
    required String code,
  }) async {
    const action = 'join';
    final sw = Stopwatch()..start();
    final context = <String, Object?>{
      'userId': userId,
      'code': maskInviteCode(code),
    };
    final normalized = normalizeInviteCode(code);
    if (normalized == null) {
      _reject(
        action,
        BudgetFailureReason.inviteNotFound,
        'code is not MLN-XXXX in Crockford base32 '
        '(length ${code.length})',
        context,
        sw,
      );
    }
    final hash = hashInviteCode(normalized);
    final now = normalizeInstant(_now());
    String? budgetId;
    final outcome = await _run<_Joined>(action, context, sw, (tx) async {
      final found = await tx.execute(
        r'SELECT budget_id FROM invites WHERE code_hash = $1',
        parameters: [hash],
        what: 'find invite by code hash',
        logParams: context,
      );
      if (found.isEmpty) {
        return const _Outcome.rejected(
          BudgetFailureReason.inviteNotFound,
          'no invite with this code',
        );
      }
      final id = found.single[0]! as String;
      budgetId = id;
      final budgetContext = {...context, 'budgetId': id};
      final budget = await tx.execute(
        r'SELECT kind, deleted_at IS NOT NULL FROM budgets '
        r'WHERE id = $1::uuid FOR UPDATE',
        parameters: [id],
        what: 'lock invited budget',
        logParams: budgetContext,
      );
      final invite = await tx.execute(
        r'SELECT budget_id, expires_at, revoked_at FROM invites '
        r'WHERE code_hash = $1',
        parameters: [hash],
        what: 'recheck invite after budget lock',
        logParams: budgetContext,
      );
      final problem = _inviteProblem(invite, budget, id, now);
      if (problem != null) {
        return _Outcome.rejected(BudgetFailureReason.inviteNotFound, problem);
      }

      final member = await tx.execute(
        r'SELECT left_at IS NOT NULL FROM budget_members '
        r'WHERE budget_id = $1::uuid AND user_id = $2::uuid',
        parameters: [id, userId],
        what: 'membership of joining user',
        logParams: budgetContext,
      );
      if (member.isNotEmpty && member.single[0] == false) {
        final rows = await tx.execute(
          'SELECT $_budgetColumns FROM budgets WHERE id = \$1::uuid',
          parameters: [id],
          what: 'read budget for already joined member',
          logParams: budgetContext,
        );
        return _Outcome.ok((
          budget: _budgetFromRow(rows.single),
          result: JoinResult.alreadyMember,
          color: null,
          reissued: null,
        ));
      }

      final used = await tx.execute(
        r'SELECT avatar_color FROM budget_members '
        r'WHERE budget_id = $1::uuid AND left_at IS NULL',
        parameters: [id],
        what: 'avatar colors of active members',
        logParams: budgetContext,
      );
      final color = _nextAvatarColor([
        for (final row in used) row[0]! as String,
      ]);
      final colorContext = {...budgetContext, 'avatarColor': color.name};
      final JoinResult result;
      if (member.isEmpty) {
        await tx.execute(
          r'INSERT INTO budget_members (budget_id, user_id, role, '
          r'avatar_color, joined_at) VALUES ($1::uuid, $2::uuid, $3, $4, '
          r'$5::timestamptz)',
          parameters: [id, userId, MemberRole.member.name, color.name, now],
          what: 'insert joined member',
          logParams: colorContext,
        );
        result = JoinResult.joined;
      } else {
        await tx.execute(
          r'UPDATE budget_members SET role = $3, avatar_color = $4, '
          r'joined_at = $5::timestamptz, left_at = NULL '
          r'WHERE budget_id = $1::uuid AND user_id = $2::uuid',
          parameters: [id, userId, MemberRole.member.name, color.name, now],
          what: 'return former member to budget',
          logParams: colorContext,
        );
        result = JoinResult.rejoined;
      }
      final reissued = await _reissue(tx, id, budgetContext);
      return _Outcome.ok((
        budget: reissued.budget,
        result: result,
        color: color,
        reissued: reissued.counts,
      ));
    });
    if (budgetId != null) context['budgetId'] = budgetId;
    final joined = _unwrap(action, outcome, context, sw);
    if (joined.result == JoinResult.alreadyMember) {
      _log.info(
        'budget $action ok result=already_member, nothing written '
        'budgetId=$budgetId userId=$userId code=${maskInviteCode(code)} '
        'in ${sw.elapsedMilliseconds}ms',
      );
    } else {
      final counts = joined.reissued!;
      _log.info(
        'budget $action ok result=${joined.result.name} '
        'budgetId=$budgetId userId=$userId code=${maskInviteCode(code)} '
        'role=${MemberRole.member.name} avatarColor=${joined.color!.name} '
        'seqReissued=budget:1,members:${counts['members']},'
        'categories:${counts['categories']},'
        'recurring:${counts['recurring']},expenses:${counts['expenses']} '
        'seq=${joined.budget.seq} in ${sw.elapsedMilliseconds}ms',
      );
    }
    return JoinedBudget(budget: joined.budget, result: joined.result);
  }

  String? _inviteProblem(
    pg.Result invite,
    pg.Result budget,
    String budgetId,
    DateTime now,
  ) {
    if (invite.isEmpty || invite.single[0] != budgetId) {
      return 'invite was replaced concurrently';
    }
    final expiresAt = invite.single[1]! as DateTime;
    final revokedAt = invite.single[2] as DateTime?;
    if (revokedAt != null) {
      return 'invite revoked at ${encodeInstant(revokedAt)}';
    }
    if (!expiresAt.isAfter(now)) {
      return 'invite expired at ${encodeInstant(expiresAt)} '
          'now=${encodeInstant(now)}';
    }
    if (budget.isEmpty) return 'budget of invite no longer exists';
    if (budget.single[1] == true) return 'budget of invite is deleted';
    if (budget.single[0] != BudgetKind.shared.name) {
      return 'invite points to a ${budget.single[0]} budget';
    }
    return null;
  }

  Future<({Budget budget, Map<String, int> counts})> _reissue(
    DbSession tx,
    String budgetId,
    Map<String, Object?> context,
  ) async {
    final budget = await tx.execute(
      'UPDATE budgets SET id = id WHERE id = \$1::uuid '
      'RETURNING $_budgetColumns',
      parameters: [budgetId],
      what: 'reissue seq of joined budget',
      logParams: context,
    );
    final counts = <String, int>{};
    for (final MapEntry(key: name, value: sql) in _reissueSql.entries) {
      final result = await tx.execute(
        sql,
        parameters: [budgetId],
        what: 'reissue seq of $name for joined member',
        logParams: context,
      );
      counts[name] = result.affectedRows;
    }
    _log.fine(
      'seq reissued so the joined member pulls the whole budget '
      '${formatContext(context)} '
      '${counts.entries.map((e) => '${e.key}=${e.value}').join(' ')}',
    );
    return (budget: _budgetFromRow(budget.single), counts: counts);
  }

  Future<LeaveResult> leave({
    required String userId,
    required String budgetId,
  }) async {
    const action = 'leave';
    final sw = Stopwatch()..start();
    final context = {'budgetId': budgetId, 'userId': userId};
    _checkBudgetId(action, budgetId, context, sw);
    final now = normalizeInstant(_now());
    final outcome = await _run<_Left>(action, context, sw, (tx) async {
      final access = await _lockBudget(tx, budgetId, userId, action);
      final denied = _denied<_Left>(access, ownerOnly: false);
      if (denied != null) return denied;
      final heirs = await tx.execute(
        r'SELECT user_id FROM budget_members '
        r'WHERE budget_id = $1::uuid AND user_id <> $2::uuid '
        r'AND left_at IS NULL ORDER BY joined_at, user_id LIMIT 1',
        parameters: [budgetId, userId],
        what: 'find earliest remaining member',
        logParams: context,
      );

      if (heirs.isEmpty) {
        final tombstones = await _tombstone(tx, budgetId, userId, now);
        await _markLeft(tx, budgetId, userId, now, 'leave as last member');
        return _Outcome.ok((
          result: LeaveResult.deleted,
          heirId: null,
          tombstones: tombstones,
          invitesRevoked: tombstones.invites,
        ));
      }

      if (access.role == MemberRole.member) {
        await _markLeft(tx, budgetId, userId, now, 'leave shared budget');
        return _Outcome.ok((
          result: LeaveResult.left,
          heirId: null,
          tombstones: null,
          invitesRevoked: 0,
        ));
      }

      final heirId = heirs.single[0]! as String;
      final transferContext = {...context, 'heirId': heirId};
      await tx.execute(
        r'UPDATE budget_members SET role = $3 '
        r'WHERE budget_id = $1::uuid AND user_id = $2::uuid',
        parameters: [budgetId, heirId, MemberRole.owner.name],
        what: 'make earliest member owner',
        logParams: transferContext,
      );
      await tx.execute(
        r'UPDATE budget_members SET role = $3, left_at = $4::timestamptz '
        r'WHERE budget_id = $1::uuid AND user_id = $2::uuid',
        parameters: [budgetId, userId, MemberRole.member.name, now],
        what: 'leave shared budget as former owner',
        logParams: transferContext,
      );
      await tx.execute(
        r'UPDATE budgets SET owner_id = $2::uuid, '
        r'updated_at = greatest(updated_at, $4::timestamptz), '
        r'updated_by = $3::uuid WHERE id = $1::uuid',
        parameters: [budgetId, heirId, userId, now],
        what: 'transfer shared budget ownership',
        logParams: transferContext,
      );
      final invites = await _revokeInvites(tx, budgetId, now);
      return _Outcome.ok((
        result: LeaveResult.transferred,
        heirId: heirId,
        tombstones: null,
        invitesRevoked: invites,
      ));
    });
    final left = _unwrap(action, outcome, context, sw);
    final details = switch (left.result) {
      LeaveResult.left => 'role=${MemberRole.member.name}',
      LeaveResult.transferred =>
        'role=${MemberRole.owner.name} newOwnerId=${left.heirId} '
            'invitesRevoked=${left.invitesRevoked}',
      LeaveResult.deleted =>
        'no members left, budget deleted '
            '${_describeTombstones(left.tombstones!)}',
    };
    _log.info(
      'budget $action ok result=${left.result.name} budgetId=$budgetId '
      'userId=$userId $details in ${sw.elapsedMilliseconds}ms',
    );
    return left.result;
  }

  Future<void> removeMember({
    required String userId,
    required String budgetId,
    required String memberId,
  }) async {
    const action = 'remove member';
    final sw = Stopwatch()..start();
    final context = {
      'budgetId': budgetId,
      'userId': userId,
      'memberId': isUuid(memberId)
          ? memberId
          : truncateBody(memberId, maxBytes: 64),
    };
    _checkBudgetId(action, budgetId, context, sw);
    final now = normalizeInstant(_now());
    final outcome = await _run<int>(action, context, sw, (tx) async {
      final access = await _lockBudget(tx, budgetId, userId, action);
      final denied = _denied<int>(access, ownerOnly: true);
      if (denied != null) return denied;
      if (memberId == userId) {
        return const _Outcome<int>.rejected(
          BudgetFailureReason.removeSelf,
          'owner tried to remove themselves, leave goes through '
          'POST /budgets/{id}/leave',
        );
      }
      if (!isUuid(memberId)) {
        return const _Outcome<int>.rejected(
          BudgetFailureReason.memberNotFound,
          'member id is not a uuid',
        );
      }
      final removed = await tx.execute(
        r'UPDATE budget_members SET left_at = $3::timestamptz '
        r'WHERE budget_id = $1::uuid AND user_id = $2::uuid '
        'AND left_at IS NULL RETURNING seq',
        parameters: [budgetId, memberId, now],
        what: 'remove member from shared budget',
        logParams: context,
      );
      if (removed.isEmpty) {
        return const _Outcome<int>.rejected(
          BudgetFailureReason.memberNotFound,
          'not an active member of this budget',
        );
      }
      return _Outcome.ok(removed.single[0]! as int);
    });
    final seq = _unwrap(action, outcome, context, sw);
    _log.info(
      'budget $action ok budgetId=$budgetId userId=$userId '
      'memberId=$memberId seq=$seq in ${sw.elapsedMilliseconds}ms',
    );
  }

  Future<void> deleteBudget({
    required String userId,
    required String budgetId,
  }) async {
    const action = 'delete';
    final sw = Stopwatch()..start();
    final context = {'budgetId': budgetId, 'userId': userId};
    _checkBudgetId(action, budgetId, context, sw);
    final now = normalizeInstant(_now());
    final outcome = await _run<_Deleted>(action, context, sw, (tx) async {
      final access = await _lockBudget(tx, budgetId, userId, action);
      final denied = _denied<_Deleted>(access, ownerOnly: true);
      if (denied != null) return denied;
      final members = await tx.execute(
        r'SELECT count(*)::int FROM budget_members '
        r'WHERE budget_id = $1::uuid AND left_at IS NULL',
        parameters: [budgetId],
        what: 'count active members of deleted budget',
        logParams: context,
      );
      final tombstones = await _tombstone(tx, budgetId, userId, now);
      return _Outcome.ok((
        members: members.single[0]! as int,
        tombstones: tombstones,
      ));
    });
    final deleted = _unwrap(action, outcome, context, sw);
    _log.info(
      'budget $action ok budgetId=$budgetId userId=$userId '
      'members=${deleted.members} '
      '${_describeTombstones(deleted.tombstones)} '
      'in ${sw.elapsedMilliseconds}ms',
    );
  }

  Future<_Tombstones> _tombstone(
    DbSession tx,
    String budgetId,
    String userId,
    DateTime now,
  ) async {
    final context = {'budgetId': budgetId, 'userId': userId};
    await tx.execute(
      r'UPDATE budgets SET deleted_at = $3::timestamptz, '
      r'updated_at = greatest(updated_at, $3::timestamptz), '
      r'updated_by = $2::uuid WHERE id = $1::uuid',
      parameters: [budgetId, userId, now],
      what: 'tombstone shared budget',
      logParams: context,
    );
    final counts = <String, int>{};
    for (final table in const ['categories', 'expenses', 'recurring_rules']) {
      final result = await tx.execute(
        'UPDATE $table SET deleted_at = \$3::timestamptz, '
        r'updated_at = greatest(updated_at, $3::timestamptz), '
        r'updated_by = $2::uuid WHERE budget_id = $1::uuid '
        'AND deleted_at IS NULL',
        parameters: [budgetId, userId, now],
        what: 'tombstone $table of shared budget',
        logParams: context,
      );
      counts[table] = result.affectedRows;
    }
    final invites = await _revokeInvites(tx, budgetId, now);
    return (
      categories: counts['categories']!,
      expenses: counts['expenses']!,
      recurring: counts['recurring_rules']!,
      invites: invites,
    );
  }

  Future<int> _revokeInvites(
    DbSession tx,
    String budgetId,
    DateTime now,
  ) async {
    final result = await tx.execute(
      r'UPDATE invites SET revoked_at = $2::timestamptz '
      r'WHERE budget_id = $1::uuid AND revoked_at IS NULL',
      parameters: [budgetId, now],
      what: 'revoke invites of budget',
      logParams: {'budgetId': budgetId},
    );
    return result.affectedRows;
  }

  Future<void> _markLeft(
    DbSession tx,
    String budgetId,
    String userId,
    DateTime now,
    String what,
  ) => tx.execute(
    r'UPDATE budget_members SET left_at = $3::timestamptz '
    r'WHERE budget_id = $1::uuid AND user_id = $2::uuid',
    parameters: [budgetId, userId, now],
    what: what,
    logParams: {'budgetId': budgetId, 'userId': userId},
  );

  Future<_Access> _lockBudget(
    DbSession tx,
    String budgetId,
    String userId,
    String action,
  ) async {
    final context = {'budgetId': budgetId, 'userId': userId};
    final budget = await tx.execute(
      r'SELECT kind, deleted_at IS NOT NULL FROM budgets '
      r'WHERE id = $1::uuid FOR UPDATE',
      parameters: [budgetId],
      what: 'lock budget for $action',
      logParams: context,
    );
    if (budget.isEmpty) {
      return const _Access(
        exists: false,
        deleted: false,
        kind: null,
        role: null,
      );
    }
    final member = await tx.execute(
      r'SELECT role FROM budget_members WHERE budget_id = $1::uuid '
      r'AND user_id = $2::uuid AND left_at IS NULL',
      parameters: [budgetId, userId],
      what: 'membership of user for $action',
      logParams: context,
    );
    return _Access(
      exists: true,
      deleted: budget.single[1]! as bool,
      kind: BudgetKind.values.byName(budget.single[0]! as String),
      role: member.isEmpty
          ? null
          : MemberRole.values.byName(member.single[0]! as String),
    );
  }

  _Outcome<T>? _denied<T>(_Access access, {required bool ownerOnly}) {
    if (!access.exists) {
      return _Outcome<T>.rejected(
        BudgetFailureReason.notFound,
        'no such budget',
      );
    }
    if (access.deleted) {
      return _Outcome<T>.rejected(
        BudgetFailureReason.notFound,
        'budget is deleted',
      );
    }
    if (access.role == null) {
      return _Outcome<T>.rejected(
        BudgetFailureReason.notFound,
        'not an active member',
      );
    }
    if (access.kind == BudgetKind.personal) {
      return _Outcome<T>.rejected(
        BudgetFailureReason.personalBudget,
        'personal budget is not shared',
      );
    }
    if (ownerOnly && access.role != MemberRole.owner) {
      return _Outcome<T>.rejected(
        BudgetFailureReason.forbidden,
        'only the owner can do this, role=${access.role!.name}',
      );
    }
    return null;
  }

  void _checkBudgetId(
    String action,
    String budgetId,
    Map<String, Object?> context,
    Stopwatch sw,
  ) {
    if (isUuid(budgetId)) return;
    context['budgetId'] = truncateBody(budgetId, maxBytes: 64);
    _reject(
      action,
      BudgetFailureReason.notFound,
      'budget id is not a uuid',
      context,
      sw,
    );
  }

  Future<_Outcome<T>> _run<T>(
    String action,
    Map<String, Object?> context,
    Stopwatch sw,
    Future<_Outcome<T>> Function(DbSession tx) body,
  ) async {
    try {
      return await db.transaction('budget $action', body);
    } catch (e) {
      _log.warning(
        'budget $action failed ${formatContext(context)} '
        'in ${sw.elapsedMilliseconds}ms: ${describeError(e)}',
      );
      rethrow;
    }
  }

  T _unwrap<T>(
    String action,
    _Outcome<T> outcome,
    Map<String, Object?> context,
    Stopwatch sw,
  ) {
    final reason = outcome.reason;
    if (reason == null) return outcome.value as T;
    _reject(action, reason, outcome.problem!, context, sw);
  }

  Never _reject(
    String action,
    BudgetFailureReason reason,
    String problem,
    Map<String, Object?> context,
    Stopwatch sw,
  ) {
    final byRights = switch (reason) {
      BudgetFailureReason.notFound ||
      BudgetFailureReason.forbidden ||
      BudgetFailureReason.personalBudget => ' by rights',
      _ => '',
    };
    _log.warning(
      'budget $action rejected$byRights reason=${_reasonCode(reason)} '
      '${formatContext(context)} ${formatContext({'problem': problem})} '
      'in ${sw.elapsedMilliseconds}ms',
    );
    throw BudgetFailure(reason, problem);
  }
}

typedef _Invite = ({String code, int attempts, int revoked});

typedef _Left = ({
  LeaveResult result,
  String? heirId,
  _Tombstones? tombstones,
  int invitesRevoked,
});

typedef _Deleted = ({int members, _Tombstones tombstones});

typedef _Joined = ({
  Budget budget,
  JoinResult result,
  CategoryColor? color,
  Map<String, int>? reissued,
});

const Map<String, String> _reissueSql = {
  'members':
      'UPDATE budget_members SET budget_id = budget_id '
      r'WHERE budget_id = $1::uuid AND left_at IS NULL',
  'categories':
      'UPDATE categories SET budget_id = budget_id '
      r'WHERE budget_id = $1::uuid',
  'recurring':
      'UPDATE recurring_rules SET budget_id = budget_id '
      r'WHERE budget_id = $1::uuid AND deleted_at IS NULL',
  'expenses':
      'UPDATE expenses SET budget_id = budget_id '
      r'WHERE budget_id = $1::uuid AND deleted_at IS NULL',
};

CategoryColor _nextAvatarColor(List<String> used) {
  for (final color in CategoryColor.values) {
    if (!used.contains(color.name)) return color;
  }
  return CategoryColor.values[used.length % CategoryColor.values.length];
}

String _reasonCode(BudgetFailureReason reason) => switch (reason) {
  BudgetFailureReason.notFound ||
  BudgetFailureReason.memberNotFound => ApiErrorCode.notFound.code,
  BudgetFailureReason.forbidden ||
  BudgetFailureReason.personalBudget => ApiErrorCode.forbidden.code,
  BudgetFailureReason.inviteNotFound => ApiErrorCode.inviteNotFound.code,
  BudgetFailureReason.removeSelf => ApiErrorCode.badRequest.code,
  BudgetFailureReason.idTaken => ApiErrorCode.conflict.code,
};

String _describeTombstones(_Tombstones t) =>
    'tombstones=categories:${t.categories},expenses:${t.expenses},'
    'recurring:${t.recurring} invitesRevoked=${t.invites}';

Budget _budgetFromRow(pg.ResultRow row) => Budget(
  id: row[0]! as String,
  kind: BudgetKind.values.byName(row[1]! as String),
  name: row[2]! as String,
  emoji: row[3]! as String,
  ownerId: row[4]! as String,
  createdAt: row[5]! as DateTime,
  updatedAt: row[6]! as DateTime,
  updatedBy: row[7]! as String,
  deletedAt: row[8] as DateTime?,
  seq: row[9]! as int,
);

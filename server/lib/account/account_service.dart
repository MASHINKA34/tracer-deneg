import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart' as pg;
import 'package:shared/shared.dart';

import '../auth/auth_service.dart';
import '../auth/password_hasher.dart';
import '../db/database.dart';

final _log = Logger('account');

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

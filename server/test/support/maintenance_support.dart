import 'dart:io';

import 'package:server/config/config.dart';
import 'package:server/db/database.dart';
import 'package:server/db/migrator.dart';
import 'package:shared/shared.dart';
import 'package:test/test.dart';

import 'test_support.dart';

const List<String> dailyJobNames = [
  'client-errors-cleanup',
  'invites-cleanup',
  'sessions-cleanup',
];

const Map<String, String> tableOfJob = {
  'client-errors-cleanup': 'client_errors',
  'invites-cleanup': 'invites',
  'sessions-cleanup': 'sessions',
};

class MaintenanceDatabase {
  MaintenanceDatabase._(this.url, this.db, this.userId, this.budgetId);

  static Future<MaintenanceDatabase> create() async {
    final url = await createScratchDatabase();
    final db = Database.open(DatabaseConfig.parse(url));
    addTearDown(() => db.close(reason: 'test done'));
    await Migrator(db, directory: Directory('migrations')).run();
    final userId = newId();
    await db.execute(
      'INSERT INTO users (id, login, display_name, password_hash, '
      r"recovery_hash) VALUES ($1::uuid, 'olga', 'Ольга', 'x', 'x')",
      parameters: [userId],
    );
    final budgetId = newId();
    await db.execute(
      'INSERT INTO budgets (id, kind, name, emoji, owner_id, created_at, '
      r"updated_at, updated_by) VALUES ($1::uuid, 'shared', 'Семья', '🏠', "
      r'$2::uuid, now(), now(), $2::uuid)',
      parameters: [budgetId, userId],
    );
    return MaintenanceDatabase._(url, db, userId, budgetId);
  }

  final String url;
  final Database db;
  final String userId;
  final String budgetId;

  Future<void> seed(DateTime now) async {
    const day = Duration(days: 1);
    for (final (label, receivedAt) in [
      ('old', now.subtract(day * 45)),
      ('fresh', now.subtract(day)),
    ]) {
      await db.execute(
        'INSERT INTO client_errors (received_at, app_version, kind, message) '
        r"VALUES ($1::timestamptz, '1.0.0+1', 'crash', $2)",
        parameters: [receivedAt, label],
      );
    }
    for (final (label, expiresAt, revokedAt) in [
      ('old', now.add(day), now.subtract(day)),
      ('fresh', now.add(const Duration(hours: 12)), null),
    ]) {
      await db.execute(
        'INSERT INTO invites (code_hash, budget_id, created_by, created_at, '
        r'expires_at, revoked_at) VALUES ($1, $2::uuid, $3::uuid, '
        r'$4::timestamptz, $5::timestamptz, $6::timestamptz)',
        parameters: [label, budgetId, userId, now, expiresAt, revokedAt],
      );
    }
    for (final (label, expiresAt, revokedAt) in [
      ('old', now.subtract(day * 20), now.subtract(day * 100)),
      ('fresh', now.add(day * 60), null),
    ]) {
      await db.execute(
        'INSERT INTO sessions (id, user_id, device_name, refresh_hash, '
        r'created_at, last_used_at, expires_at, revoked_at) VALUES ($1::uuid, '
        r'$2::uuid, $3, $4, $5::timestamptz, $5::timestamptz, '
        r'$6::timestamptz, $7::timestamptz)',
        parameters: [
          newId(),
          userId,
          label,
          'refresh-$label',
          now.subtract(day * 120),
          expiresAt,
          revokedAt,
        ],
      );
    }
  }

  Future<Map<String, List<String>>> remaining() async => {
    'client_errors': await _labels('SELECT message FROM client_errors'),
    'invites': await _labels('SELECT code_hash FROM invites'),
    'sessions': await _labels('SELECT device_name FROM sessions'),
  };

  Future<void> breakTable(String table) =>
      db.execute('ALTER TABLE $table RENAME TO ${table}_broken');

  Future<void> repairTable(String table) =>
      db.execute('ALTER TABLE ${table}_broken RENAME TO $table');

  Future<List<String>> _labels(String sql) async {
    final rows = await db.execute('$sql ORDER BY 1');
    return [for (final row in rows) row.first! as String];
  }
}

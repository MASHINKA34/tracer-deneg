import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/data/current_user.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/repositories/budgets_repository.dart';
import 'package:milionchik/data/repositories/outbox_queue.dart';
import 'package:milionchik/data/repositories/prefs_repository.dart';

AppDatabase openTestDatabase() {
  final db = AppDatabase(
    DatabaseConnection(
      NativeDatabase.memory(),
      closeStreamsSynchronously: true,
    ),
  );
  addTearDown(db.close);
  return db;
}

BudgetsRepository testBudgets(AppDatabase db) => DriftBudgetsRepository(
  db,
  currentUser: LocalPrefsCurrentUser(DriftPrefsRepository(db)),
  outbox: DriftOutboxQueue(db),
);

Widget withDatabase(AppDatabase db, Widget child) => ProviderScope(
  overrides: [appDatabaseProvider.overrideWithValue(db)],
  child: child,
);

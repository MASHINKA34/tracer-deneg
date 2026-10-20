import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/data/db/app_database.dart';

import 'app_database/generated/schema.dart';

const _strict = ValidationOptions(validateDropped: true);

void main() {
  final latest = GeneratedHelper.versions.last;
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('для текущей версии схемы есть снимок', () async {
    final db = AppDatabase.memory();
    addTearDown(db.close);
    expect(
      latest,
      db.schemaVersion,
      reason:
          'нет снимка схемы версии ${db.schemaVersion}: '
          'cd app; dart run drift_dev make-migrations',
    );
  });

  test('база версии $latest из снимка совпадает с текущей схемой', () async {
    final db = AppDatabase(await verifier.startAt(latest));
    addTearDown(db.close);
    await db.validateDatabaseSchema(options: _strict);
  });

  test('новая база совпадает со снимком версии $latest', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, latest, options: _strict);
  });
}

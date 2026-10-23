import 'package:shared/shared.dart';

import '../db/database.dart';
import 'client_error_fields.dart';

final class StoredClientError {
  const StoredClientError({required this.id, required this.receivedAt});

  final String id;
  final DateTime receivedAt;
}

final class ClientErrorRow {
  const ClientErrorRow({
    required this.id,
    required this.receivedAt,
    required this.userId,
    required this.appVersion,
    required this.androidSdk,
    required this.deviceModel,
    required this.kind,
    required this.message,
    required this.stackBytes,
    required this.logsBytes,
  });

  final String id;
  final DateTime receivedAt;
  final String? userId;
  final String appVersion;
  final int? androidSdk;
  final String? deviceModel;
  final String kind;
  final String message;
  final int? stackBytes;
  final int? logsBytes;
}

final class ClientErrorPage {
  const ClientErrorPage({required this.rows, required this.total});

  final List<ClientErrorRow> rows;
  final int total;
}

const int clientErrorListMessageChars = 500;

class ClientErrorStore {
  ClientErrorStore(this.db);

  final Database db;

  Future<StoredClientError> insert(
    PreparedClientError report, {
    String? userId,
  }) async {
    final rows = await db.execute(
      r'INSERT INTO client_errors (user_id, app_version, android_sdk, '
      r'device_model, kind, message, stack, logs) VALUES ($1::uuid, $2, '
      r'$3::int, $4, $5, $6, $7, $8) RETURNING id::text, received_at',
      parameters: [
        userId,
        report.appVersion,
        report.androidSdk,
        report.deviceModel,
        report.kind.code,
        report.message,
        report.stack,
        report.logs,
      ],
      what: 'insert client error',
      logParams: {
        'kind': report.kind.code,
        'userId': userId ?? 'none',
        'messageBytes': report.messageBytes,
        'stackBytes': report.stackBytes,
        'logsBytes': report.logsBytes,
      },
    );
    final row = rows.first;
    return StoredClientError(
      id: row[0]! as String,
      receivedAt: (row[1]! as DateTime).toUtc(),
    );
  }

  Future<int> deleteReceivedBefore(DateTime cutoff) async {
    final result = await db.execute(
      r'DELETE FROM client_errors WHERE received_at < $1::timestamptz',
      parameters: [normalizeInstant(cutoff)],
      what: 'delete old client errors',
      logParams: {'before': encodeInstant(cutoff)},
    );
    return result.affectedRows;
  }

  Future<ClientErrorPage> listSince(
    DateTime since, {
    required int limit,
  }) async {
    final rows = await db.execute(
      'SELECT id::text, received_at, user_id::text, app_version, android_sdk, '
      'device_model, kind, left(message, $clientErrorListMessageChars), '
      'octet_length(stack), octet_length(logs), count(*) OVER ()::int '
      r'FROM client_errors WHERE received_at >= $1::timestamptz '
      r'ORDER BY received_at DESC, id LIMIT $2::int',
      parameters: [normalizeInstant(since), limit],
      what: 'list client errors',
      logParams: {'since': encodeInstant(since), 'limit': limit},
    );
    return ClientErrorPage(
      rows: [
        for (final row in rows)
          ClientErrorRow(
            id: row[0]! as String,
            receivedAt: (row[1]! as DateTime).toUtc(),
            userId: row[2] as String?,
            appVersion: row[3]! as String,
            androidSdk: row[4] as int?,
            deviceModel: row[5] as String?,
            kind: row[6]! as String,
            message: row[7]! as String,
            stackBytes: row[8] as int?,
            logsBytes: row[9] as int?,
          ),
      ],
      total: rows.isEmpty ? 0 : rows.first[10]! as int,
    );
  }
}

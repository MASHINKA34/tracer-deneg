import '../client_errors/client_error_store.dart';
import '../db/database.dart';
import 'client_errors_cleanup.dart';
import 'daily_jobs.dart';
import 'invites_cleanup.dart';
import 'sessions_cleanup.dart';

List<DailyJob> dailyJobList(
  Database db, {
  DateTime Function() now = DateTime.now,
}) => [
  ClientErrorsCleanup(store: ClientErrorStore(db), now: now).job,
  InvitesCleanup(db: db, now: now).job,
  SessionsCleanup(db: db, now: now).job,
];

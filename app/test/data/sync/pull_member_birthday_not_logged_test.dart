import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/data/api/api_exception.dart';
import 'package:milionchik/data/db/app_database.dart';
import 'package:milionchik/data/sync/pull_service.dart';
import 'package:shared/shared.dart';

import '../api/fake_api_adapter.dart';
import 'pull_fixture.dart';

typedef _Broken = ({int? month, int? day, String leak});

const List<_Broken> _broken = [
  (month: 7, day: null, leak: '7/null'),
  (month: 11, day: 31, leak: '11/31'),
];

Map<String, Object?> _page(_Broken broken) => {
  ...SyncPullResponse(cursor: 4100, hasMore: false).toJson(),
  'profiles': [
    {
      'userId': 'user-member-dima',
      'displayName': 'Дима',
      'avatarColor': 'green',
      'birthdayMonth': broken.month,
      'birthdayDay': broken.day,
    },
  ],
};

void main() {
  late LogCapture logs;
  late AppDatabase db;

  setUp(() {
    logs = LogCapture();
    db = AppDatabase.memory();
  });

  tearDown(() async {
    await logs.dispose();
    await db.close();
  });

  for (final broken in _broken) {
    test('pull: битая дата рождения участника ${broken.leak} - warn и ошибка '
        'pull без месяца и дня, в sync_state.lastError тоже', () async {
      final server = FakePullServer(const [])
        ..before[1] = (_) => FakeReply.json(200, _page(broken));
      final rig = PullRig(db, server);

      Object? thrown;
      try {
        await rig.service().pull(PullReason.manual);
      } catch (e) {
        thrown = e;
      }

      expect(thrown, isA<PullFailure>());
      final failure = thrown! as PullFailure;
      expect(failure.error, isA<ApiBadResponse>());
      expect(failure.description, isNot(contains(broken.leak)));
      expect(
        failure.description,
        contains('birthdayMonth/birthdayDay: not a valid month and day'),
      );

      final warn = logs.linesOf('sync', Level.WARNING);
      expect(
        warn,
        contains(
          matches(
            r'WARN  \[sync\] GET /sync/pull 200 cursor=0 answered without a '
            r'pull page → bad response: birthdayMonth/birthdayDay: not a valid '
            r'month and day \(values not logged\) rid=ridpull\d+$',
          ),
        ),
      );
      final text = logs.text;
      expect(text, contains('pull failed reason=manual stage=request'));
      expect(text, isNot(contains(broken.leak)), reason: text);
      expect(text, isNot(contains('Birthday needs')), reason: text);
      expect(text, isNot(contains('Invalid birthday')), reason: text);

      final state = await rig.syncState();
      expect(state.cursor, 0);
      expect(state.lastError, contains('ApiBadResponse'));
      expect(state.lastError, isNot(contains(broken.leak)));
    });
  }
}

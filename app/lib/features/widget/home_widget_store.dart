import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart';

import 'home_widget_data.dart';

final _log = Logger('widget');

abstract interface class HomeWidgetStorage {
  Future<bool?> save(String key, String value);

  Future<bool?> redraw(String qualifiedAndroidName);
}

final class PluginHomeWidgetStorage implements HomeWidgetStorage {
  const PluginHomeWidgetStorage();

  @override
  Future<bool?> save(String key, String value) =>
      HomeWidget.saveWidgetData<String>(key, value);

  @override
  Future<bool?> redraw(String qualifiedAndroidName) =>
      HomeWidget.updateWidget(qualifiedAndroidName: qualifiedAndroidName);
}

final class HomeWidgetDataNotSaved implements Exception {
  const HomeWidgetDataNotSaved(this.key);

  final String key;

  @override
  String toString() =>
      'HomeWidgetDataNotSaved: SharedPreferences commit of key=$key '
      'returned false';
}

final class HomeWidgetStore {
  const HomeWidgetStore([this._storage = const PluginHomeWidgetStorage()]);

  final HomeWidgetStorage _storage;

  Future<void> show(HomeWidgetData data, {required String reason}) async {
    final sw = Stopwatch()..start();
    final json = data.encode();
    final bytes = utf8.encode(json).length;
    _log.fine(
      'home widget data reason=$reason ${data.describe()} bytes=$bytes '
      'json=${truncateBody(json)}',
    );

    bool? saved;
    try {
      saved = await _storage.save(homeWidgetDataKey, json);
    } catch (e, st) {
      _log.severe(
        'home widget data not saved reason=$reason ${data.describe()} '
        'key=$homeWidgetDataKey bytes=$bytes after '
        '${sw.elapsedMilliseconds}ms: ${describeError(e)}',
        e,
        st,
      );
      rethrow;
    }
    if (saved != true) {
      const error = HomeWidgetDataNotSaved(homeWidgetDataKey);
      _log.severe(
        'home widget data not saved reason=$reason ${data.describe()} '
        'bytes=$bytes after ${sw.elapsedMilliseconds}ms: storage answered '
        'saved=$saved → the widget keeps the previous data',
        error,
      );
      throw error;
    }

    try {
      await _storage.redraw(homeWidgetAndroidProvider);
    } catch (e, st) {
      _log.severe(
        'home widget redraw request failed reason=$reason '
        'provider=$homeWidgetAndroidProvider after '
        '${sw.elapsedMilliseconds}ms, the data is saved and shows on the '
        'next system update: ${describeError(e)}',
        e,
        st,
      );
      rethrow;
    }
    _log.info(
      'home widget data saved reason=$reason ${data.describe()} '
      'bytes=$bytes in ${sw.elapsedMilliseconds}ms → redraw requested',
    );
  }
}

final homeWidgetStoreProvider = Provider<HomeWidgetStore>(
  (ref) => const HomeWidgetStore(),
  name: 'homeWidgetStore',
);

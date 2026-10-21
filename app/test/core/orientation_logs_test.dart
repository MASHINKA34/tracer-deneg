import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:milionchik/core/orientation_policy.dart';

final class _Policy {
  _Policy._(this.records, this.orientationCalls);

  final List<LogRecord> records;
  final List<Object?> orientationCalls;

  static _Policy start(
    WidgetTester tester, {
    required Size size,
    double pixelRatio = 1,
  }) {
    final policy = _Policy._([], []);
    final previousLevel = Logger.root.level;
    Logger.root.level = Level.ALL;
    final sub = Logger.root.onRecord
        .where((r) => r.loggerName == 'orientation')
        .listen(policy.records.add);
    addTearDown(() async {
      await sub.cancel();
      Logger.root.level = previousLevel;
    });

    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemChrome.setPreferredOrientations') {
          policy.orientationCalls.add(call.arguments);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    tester.view
      ..devicePixelRatio = pixelRatio
      ..physicalSize = size * pixelRatio;
    addTearDown(tester.view.reset);

    final observer = OrientationPolicy()..start();
    addTearDown(() => WidgetsBinding.instance.removeObserver(observer));
    return policy;
  }

  Iterable<String> debug() =>
      records.where((r) => r.level == Level.FINE).map((r) => r.message);

  Iterable<String> info() =>
      records.where((r) => r.level == Level.INFO).map((r) => r.message);
}

void main() {
  testWidgets('планшет: старт и поворот в debug-логе orientation — ширина, '
      'высота, sw, ориентация и колонка 480 по центру; категория не меняется '
      '— info только при старте', (tester) async {
    final policy = _Policy.start(tester, size: const Size(800, 1280));

    tester.view.physicalSize = const Size(1280, 800);
    await tester.pump();
    tester.view.physicalSize = const Size(800, 1280);
    await tester.pump();

    expect(policy.debug(), [
      'window 800x1280dp sw=800dp portrait, content 480dp centered (start)',
      'window 800x1280dp → 1280x800dp sw=800dp portrait → landscape, '
          'content 480dp centered (window metrics changed)',
      'window 1280x800dp → 800x1280dp sw=800dp landscape → portrait, '
          'content 480dp centered (window metrics changed)',
    ]);
    expect(policy.info(), [
      'any orientation: shortestSide=800dp size=800x1280dp (start)',
    ]);
    expect(policy.orientationCalls, [<Object?>[]]);
  });

  testWidgets('смена отступов и клавиатуры без смены размера окна в лог не '
      'попадает', (tester) async {
    final policy = _Policy.start(tester, size: const Size(800, 1280));

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 48);
    await tester.pump();

    expect(policy.debug(), [
      'window 800x1280dp sw=800dp portrait, content 480dp centered (start)',
    ]);
  });

  testWidgets('раскладушку сложили и раскрыли: размер, sw и ориентация в '
      'debug, смена категории в info, ориентация телефона — только портрет', (
    tester,
  ) async {
    final policy = _Policy.start(tester, size: const Size(840, 900));

    tester.view.physicalSize = const Size(412, 915);
    await tester.pump();
    tester.view.physicalSize = const Size(900, 840);
    await tester.pump();

    expect(policy.debug(), [
      'window 840x900dp sw=840dp portrait, content 480dp centered (start)',
      'window 840x900dp → 412x915dp sw=412dp portrait, content full width '
          '(window metrics changed)',
      'window 412x915dp → 900x840dp sw=840dp portrait → landscape, content '
          '480dp centered (window metrics changed)',
    ]);
    expect(policy.info(), [
      'any orientation: shortestSide=840dp size=840x900dp (start)',
      'portrait only: shortestSide=412dp size=412x915dp '
          '(window metrics changed)',
      'any orientation: shortestSide=840dp size=900x840dp '
          '(window metrics changed)',
    ]);
    expect(policy.orientationCalls, [
      <Object?>[],
      ['DeviceOrientation.portraitUp'],
      <Object?>[],
    ]);
  });

  testWidgets('телефон 1080×2400 при 3× плотности: 360x800dp во всю ширину; '
      'wm density 540 — 320x711dp', (tester) async {
    final policy = _Policy.start(
      tester,
      size: const Size(360, 800),
      pixelRatio: 3,
    );

    tester.view.devicePixelRatio = 540 / 160;
    await tester.pump();

    expect(policy.debug(), [
      'window 360x800dp sw=360dp portrait, content full width (start)',
      'window 360x800dp → 320x711dp sw=320dp portrait, content full width '
          '(window metrics changed)',
    ]);
    expect(policy.info(), [
      'portrait only: shortestSide=360dp size=360x800dp (start)',
    ]);
  });
}

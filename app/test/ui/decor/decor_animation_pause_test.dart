import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:milionchik/l10n/app_localizations.dart';
import 'package:milionchik/ui/catalog/demo_months.dart';
import 'package:milionchik/ui/components/day_cell.dart';
import 'package:milionchik/ui/components/month_card.dart';
import 'package:milionchik/ui/decor/decor_painter.dart';
import 'package:milionchik/ui/theme/app_theme.dart';
import 'package:shared/shared.dart';

import '../../data/api/fake_api_adapter.dart' show LogCapture;

const Key _cardKey = ValueKey('card');
final RegExp _stateLine = RegExp(
  r'^decor animation (started|paused|not started|stopped) ',
);
const Duration _frame = Duration(milliseconds: 16);

final class _Card {
  _Card(this.tester, this.logs);

  final WidgetTester tester;
  final LogCapture logs;
  final ValueNotifier<bool> tickers = ValueNotifier(true);
  final ValueNotifier<Mood> mood = ValueNotifier(Mood.newyear);
  final ScrollController scroll = ScrollController();

  RenderRepaintBoundary get decor => tester.renderObject(
    find
        .ancestor(
          of: find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is DecorPainter,
          ),
          matching: find.byType(RepaintBoundary),
        )
        .first,
  );

  RenderRepaintBoundary get card => tester.renderObject(find.byKey(_cardKey));

  static int paints(RenderRepaintBoundary b) =>
      b.debugSymmetricPaintCount + b.debugAsymmetricPaintCount;

  ui.Picture? get decorPicture =>
      (decor.debugLayer?.firstChild as PictureLayer?)?.picture;

  Future<int> decorFrames([int frames = 12]) async {
    var changed = 0;
    var last = decorPicture;
    for (var i = 0; i < frames; i++) {
      await tester.pump(_frame);
      final now = decorPicture;
      if (!identical(now, last)) changed++;
      last = now;
    }
    return changed;
  }

  List<String> get decorLines => [
    for (final r in logs.records)
      if (r.loggerName == 'decor' && _stateLine.hasMatch(r.message)) r.message,
  ];

  void dispose() {
    tickers.dispose();
    mood.dispose();
    scroll.dispose();
  }
}

Future<_Card> _pumpCard(WidgetTester tester) async {
  final logs = LogCapture();
  addTearDown(logs.dispose);
  final card = _Card(tester, logs);
  addTearDown(card.dispose);
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(360, 800);
  addTearDown(tester.view.reset);
  final demo = demoNewYear;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(Brightness.light, Mood.newyear),
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: ValueListenableBuilder<bool>(
        valueListenable: card.tickers,
        builder: (context, tickers, _) => TickerMode(
          enabled: tickers,
          child: Material(
            child: SingleChildScrollView(
              controller: card.scroll,
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  RepaintBoundary(
                    key: _cardKey,
                    child: ValueListenableBuilder<Mood>(
                      valueListenable: card.mood,
                      builder: (context, mood, _) => MonthCard(
                        month: demo.month,
                        today: demo.today,
                        dayTotals: demo.dayTotals,
                        mood: mood,
                        holidayMarks: demo.marks,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2000),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return card;
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  tearDown(DecorPainter.clearCache);

  testWidgets('Новый год, приложение на экране: декор перерисовывается '
      'каждый кадр, а остальная карточка не перерисовывается и не '
      'перестраивается', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final card = await _pumpCard(tester);
    await tester.pump(_frame);
    final cardPaints = _Card.paints(card.card);
    final cell = tester.widget<DayCell>(find.byType(DayCell).first);

    expect(await card.decorFrames(30), 30);
    expect(tester.binding.hasScheduledFrame, isTrue);
    expect(_Card.paints(card.card), cardPaints);
    expect(tester.widget<DayCell>(find.byType(DayCell).first), same(cell));
    expect(card.decorLines, [
      'decor animation started holiday=newyear layer=newyear cycle=6000ms '
          'trigger=card shown',
    ]);
  });

  testWidgets('системное «Удалить анимацию»: декор замирает и не просит '
      'кадров; включили обратно - анимация снова идёт', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final card = await _pumpCard(tester);
    expect(await card.decorFrames(), 12);

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pump();
    expect(await card.decorFrames(), 0);
    expect(tester.binding.hasScheduledFrame, isFalse);

    tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
    await tester.pump();
    expect(await card.decorFrames(), 12);
    expect(card.decorLines, [
      'decor animation started holiday=newyear layer=newyear cycle=6000ms '
          'trigger=card shown',
      matches(
        r'^decor animation paused holiday=newyear layer=newyear '
        r'reason=system animations disabled after \d+ms$',
      ),
      'decor animation started holiday=newyear layer=newyear cycle=6000ms '
          'trigger=system animations enabled',
    ]);
  });

  testWidgets('анимации выключены ещё до открытия: карточка сразу '
      'статичная, кадров нет; включили - пошла', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final card = await _pumpCard(tester);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(await card.decorFrames(), 0);

    tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
    await tester.pump();
    expect(await card.decorFrames(), 12);
    expect(card.decorLines, [
      'decor animation not started holiday=newyear layer=newyear '
          'reason=system animations disabled → static picture',
      'decor animation started holiday=newyear layer=newyear cycle=6000ms '
          'trigger=system animations enabled',
    ]);
  });

  testWidgets('приложение свернули - пауза и ни одного кадра, вернули - '
      'анимация снова идёт; неактивное окно поверх (inactive) не мешает', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final card = await _pumpCard(tester);
    expect(await card.decorFrames(), 12);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(await card.decorFrames(), 12);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(await card.decorFrames(), 0);
    expect(tester.binding.hasScheduledFrame, isFalse);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(await card.decorFrames(), 12);
    expect(card.decorLines, [
      'decor animation started holiday=newyear layer=newyear cycle=6000ms '
          'trigger=card shown',
      matches(
        r'^decor animation paused holiday=newyear layer=newyear '
        r'reason=app in background \(hidden\) after \d+ms$',
      ),
      'decor animation started holiday=newyear layer=newyear cycle=6000ms '
          'trigger=app inactive',
    ]);
  });

  testWidgets('состояние приложения ещё неизвестно - декор статичный; '
      'пришло resumed - анимация пошла', (tester) async {
    final card = await _pumpCard(tester);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(await card.decorFrames(), 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(await card.decorFrames(), 12);
    expect(card.decorLines, [
      'decor animation not started holiday=newyear layer=newyear '
          'reason=app lifecycle unknown → static picture',
      'decor animation started holiday=newyear layer=newyear cycle=6000ms '
          'trigger=app resumed',
    ]);
  });

  testWidgets('экран скрыт (другая вкладка или экран сверху, TickerMode) - '
      'пауза; снова виден - анимация идёт', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final card = await _pumpCard(tester);
    expect(await card.decorFrames(), 12);

    card.tickers.value = false;
    await tester.pump();
    expect(await card.decorFrames(), 0);
    expect(tester.binding.hasScheduledFrame, isFalse);

    card.tickers.value = true;
    await tester.pump();
    expect(await card.decorFrames(), 12);
    expect(card.decorLines, [
      'decor animation started holiday=newyear layer=newyear cycle=6000ms '
          'trigger=card shown',
      matches(
        r'^decor animation paused holiday=newyear layer=newyear '
        r'reason=screen hidden \(another tab or screen on top\) after \d+ms$',
      ),
      'decor animation started holiday=newyear layer=newyear cycle=6000ms '
          'trigger=screen visible again',
    ]);
  });

  testWidgets('карточку прокрутили за край экрана - пауза; вернули хоть '
      'краешком - анимация идёт', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final card = await _pumpCard(tester);
    expect(await card.decorFrames(), 12);

    final height = tester.getSize(find.byType(MonthCard)).height;
    card.scroll.jumpTo(height + 13);
    await tester.pump();
    await tester.pump();
    expect(await card.decorFrames(), 0);
    expect(tester.binding.hasScheduledFrame, isFalse);

    card.scroll.jumpTo(height + 4);
    await tester.pump();
    await tester.pump();
    expect(await card.decorFrames(), 12);
    expect(card.decorLines, [
      'decor animation started holiday=newyear layer=newyear cycle=6000ms '
          'trigger=card shown',
      matches(
        r'^decor animation paused holiday=newyear layer=newyear '
        r'reason=card scrolled out of view after \d+ms$',
      ),
      'decor animation started holiday=newyear layer=newyear cycle=6000ms '
          'trigger=scrolled into view',
    ]);
  });

  testWidgets('карточка сменила праздник на сезон - анимация остановилась, '
      'сезон не тикает; снова праздник - пошла с новым циклом', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final card = await _pumpCard(tester);
    expect(await card.decorFrames(), 12);

    card.mood.value = Mood.autumn;
    await tester.pump();
    expect(await card.decorFrames(), 0);
    expect(tester.binding.hasScheduledFrame, isFalse);

    card.mood.value = Mood.valentine;
    await tester.pump();
    expect(await card.decorFrames(), 12);
    expect(card.decorLines, [
      'decor animation started holiday=newyear layer=newyear cycle=6000ms '
          'trigger=card shown',
      matches(
        r'^decor animation paused holiday=newyear layer=newyear '
        r'reason=layer changed newyear → autumn after \d+ms$',
      ),
      'decor animation started holiday=valentine layer=valentine '
          'cycle=1200ms trigger=layer changed autumn → valentine',
    ]);
  });
}

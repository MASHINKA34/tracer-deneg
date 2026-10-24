import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/core/clock.dart';
import 'package:milionchik/core/router.dart';
import 'package:milionchik/data/providers.dart';
import 'package:milionchik/data/sync/sync_status_view.dart';
import 'package:milionchik/features/month/month_header.dart';
import 'package:milionchik/features/month/sync_status_popover.dart';
import 'package:milionchik/l10n/app_localizations.dart';
import 'package:milionchik/ui/theme/app_theme.dart';
import 'package:shared/shared.dart';

import '../../features/month/month_fixture.dart';
import '../../support/app_scope.dart';
import '../../support/golden.dart';
import '../../support/test_fonts.dart';

final DateTime _lastSync = testNow.subtract(const Duration(minutes: 2));

const String _waitingLabel = 'Ждёт сети · 3';

void main() {
  for (final brightness in Brightness.values) {
    for (final width in const [360.0, 320.0]) {
      for (final scale in const [1.0, 2.0]) {
        final name =
            'screen_${brightness.name}_${width.toInt()}'
            '${scale == 1 ? '' : '_x${scale.toInt()}'}';
        testWidgets(
          'главная · нет сети, плашка статуса $name (Figma 47:6011)',
          (tester) async {
            await loadTestFonts();
            final db = openTestDatabase();
            await tester.runAsync(() => seedMockupOctober(db));
            debugDisableShadows = false;
            tester.view
              ..devicePixelRatio = goldenPixelRatio
              ..physicalSize = Size(width, 800) * goldenPixelRatio
              ..viewPadding = const FakeViewPadding(top: 32)
              ..padding = const FakeViewPadding(top: 32);
            addTearDown(tester.view.reset);
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(tester.platformDispatcher.clearAllTestValues);
            final router = buildRouter();
            addTearDown(router.dispose);
            final base = AppTheme.build(brightness, Mood.autumn);

            await tester.pumpWidget(
              ProviderScope(
                overrides: [
                  appDatabaseProvider.overrideWithValue(db),
                  clockProvider.overrideWithValue(Clock(now: () => testNow)),
                  syncStatusViewProvider.overrideWithBuild(
                    (ref, _) => SyncStatusView(
                      shown: SyncShown.waiting,
                      queue: 3,
                      lastSyncAt: _lastSync,
                    ),
                  ),
                ],
                child: RepaintBoundary(
                  key: goldenKey,
                  child: MaterialApp.router(
                    debugShowCheckedModeBanner: false,
                    theme: base.copyWith(
                      textTheme: base.textTheme.apply(
                        fontFamilyFallback: const [testEmojiFamily],
                      ),
                    ),
                    locale: const Locale('ru'),
                    supportedLocales: AppLocalizations.supportedLocales,
                    localizationsDelegates:
                        AppLocalizations.localizationsDelegates,
                    routerConfig: router,
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            await tester.tap(
              find.descendant(
                of: find.byType(MonthHeader),
                matching: find.bySemanticsLabel(_waitingLabel),
              ),
            );
            await tester.pumpAndSettle();
            await settleAssets(tester);
            expect(find.byType(SyncStatusPopover), findsOneWidget);

            await expectGolden(tester, 'sync_status', name);
          },
        );
      }
    }
  }

  for (final (state, view) in [
    ('done', SyncStatusView(shown: SyncShown.done, lastSyncAt: _lastSync)),
    (
      'sending',
      SyncStatusView(shown: SyncShown.sending, queue: 3, lastSyncAt: _lastSync),
    ),
    (
      'waiting',
      SyncStatusView(shown: SyncShown.waiting, queue: 3, lastSyncAt: _lastSync),
    ),
    ('error', const SyncStatusView(shown: SyncShown.error, queue: 3)),
  ]) {
    for (final brightness in Brightness.values) {
      for (final scale in [1.0, if (state == 'error') 2.0]) {
        final name =
            'popover_${state}_${brightness.name}'
            '${scale == 1 ? '' : '_x${scale.toInt()}'}';
        testWidgets('плашка статуса $name', (tester) async {
          await pumpGolden(
            tester,
            brightness: brightness,
            textScale: scale,
            width: scale == 1 ? 290 : 360,
            padding: scale == 1
                ? const EdgeInsets.fromLTRB(20, 16, 20, 40)
                : const EdgeInsets.fromLTRB(12, 16, 12, 40),
            child: SyncStatusPopover(view: view, now: testNow, onRetry: () {}),
          );
          await tester.pump(const Duration(milliseconds: 250));

          await expectGolden(tester, 'sync_status', name);
        });
      }
    }
  }
}

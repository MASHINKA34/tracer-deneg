import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';

import '../../core/router.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/components/fitting_text.dart';
import '../../ui/components/radio.dart';
import '../../ui/components/snackbar.dart';
import '../../ui/theme/app_text.dart';
import '../../ui/theme/app_theme.dart';
import '../categories/categories_top_bar.dart';
import 'profile_budgets.dart' show ProfileCard;
import 'theme_mode.dart';

final _log = Logger('profile');

final _nav = Logger('nav');

class ThemeScreen extends ConsumerStatefulWidget {
  const ThemeScreen({super.key});

  @override
  ConsumerState<ThemeScreen> createState() => _ThemeScreenState();
}

class _ThemeScreenState extends ConsumerState<ThemeScreen> {
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _log.fine('theme screen opened mode=${ref.read(themeModeProvider).name}');
  }

  Future<void> _choose(ThemeMode mode) async {
    if (_saving) {
      _log.fine('theme mode=${mode.name} tap ignored: previous choice saving');
      return;
    }
    _log.fine('theme option tap mode=${mode.name}');
    _saving = true;
    final saved = await ref.read(themeModeProvider.notifier).set(mode);
    _saving = false;
    if (saved || !mounted) return;
    showAppSnackbar(
      context,
      text: AppLocalizations.of(context).themeSaveFailed,
    );
  }

  void _back() {
    if (context.canPop()) {
      _nav.fine('theme closed by back button');
      context.pop();
      return;
    }
    _nav.fine('theme closed with nothing under it → ${AppRoutes.profile}');
    context.go(AppRoutes.profile);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.colors;
    final mode = ref.watch(themeModeProvider);
    final systemDark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    return Scaffold(
      backgroundColor: colors.bgApp,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SafeArea(
            bottom: false,
            child: CategoriesTopBar(title: l10n.themeTitle, onBack: _back),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                12,
                4,
                12,
                16 + MediaQuery.paddingOf(context).bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ProfileCard(
                    children: [
                      _ThemeOption(
                        title: l10n.themeSystem,
                        caption: systemDark
                            ? l10n.themeSystemNowDark
                            : l10n.themeSystemNowLight,
                        selected: mode == ThemeMode.system,
                        onTap: () => _choose(ThemeMode.system),
                      ),
                      _ThemeOption(
                        title: l10n.themeLight,
                        selected: mode == ThemeMode.light,
                        onTap: () => _choose(ThemeMode.light),
                      ),
                      _ThemeOption(
                        title: l10n.themeDark,
                        selected: mode == ThemeMode.dark,
                        onTap: () => _choose(ThemeMode.dark),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.themeNote,
                    style: AppText.caption.copyWith(color: colors.textTertiary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.title,
    this.caption,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String? caption;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final caption = this.caption;
    return MergeSemantics(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 2, 0),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittingText(
                        title,
                        style: AppText.bodyL.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      if (caption != null) ...[
                        const SizedBox(height: 2),
                        FittingText(
                          caption,
                          style: AppText.caption.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              AppRadio(selected: selected, onTap: onTap),
            ],
          ),
        ),
      ),
    );
  }
}

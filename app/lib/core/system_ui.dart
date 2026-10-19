import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Прозрачные системные панели (edge-to-edge); иконки тёмные в светлой
/// теме и светлые в тёмной (00-spec §3).
SystemUiOverlayStyle systemUiStyleFor(Brightness themeBrightness) {
  final iconBrightness = themeBrightness == Brightness.light
      ? Brightness.dark
      : Brightness.light;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: iconBrightness,
    statusBarBrightness: themeBrightness,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: iconBrightness,
    systemStatusBarContrastEnforced: false,
    systemNavigationBarContrastEnforced: false,
  );
}

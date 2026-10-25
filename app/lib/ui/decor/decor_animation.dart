import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'package:shared/shared.dart' show Mood;

import 'decor_generator.dart';
import 'decor_motion.dart';
import 'decor_painter.dart';

final _log = Logger('decor');

class AnimatedDecor extends StatefulWidget {
  const AnimatedDecor({
    super.key,
    required this.mood,
    required this.brightness,
    this.phase = 0,
    this.cornerRadius = 28,
  });

  final Mood mood;
  final ui.Brightness brightness;
  final double phase;
  final double cornerRadius;

  @override
  State<AnimatedDecor> createState() => _AnimatedDecorState();
}

class _AnimatedDecorState extends State<AnimatedDecor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this)
    ..addStatusListener(_statusChanged);
  late final AppLifecycleListener _lifecycle;
  final Stopwatch _runTime = Stopwatch();
  ScrollableState? _scrollable;
  ScrollPosition? _position;
  bool _shown = false;
  bool _disabled = false;
  bool _tickers = true;
  bool _onScreen = true;
  bool _checkQueued = false;
  bool _running = false;
  bool _opening = true;
  String? _blocked;

  DecorLayer get _layer => decorLayerOf(
    widget.mood.name,
    dark: widget.brightness == ui.Brightness.dark,
  );

  String get _what => 'holiday=${widget.mood.name} layer=${_layer.key}';

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onStateChange: _lifecycleChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disabled = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final tickers = TickerMode.valuesOf(context).enabled;
    final String trigger;
    if (!_shown) {
      trigger = 'card shown';
    } else if (disabled != _disabled) {
      trigger = disabled
          ? 'system animations disabled'
          : 'system animations enabled';
    } else if (tickers != _tickers) {
      trigger = tickers ? 'screen visible again' : 'screen hidden';
    } else {
      trigger = 'surroundings changed';
    }
    _shown = true;
    _disabled = disabled;
    _tickers = tickers;
    _scrollable = Scrollable.maybeOf(context);
    final position = _scrollable?.position;
    if (!identical(position, _position)) {
      _position?.removeListener(_queueVisibilityCheck);
      _position = position?..addListener(_queueVisibilityCheck);
    }
    _update(trigger);
    _queueVisibilityCheck();
  }

  @override
  void didUpdateWidget(AnimatedDecor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = decorLayerOf(
      oldWidget.mood.name,
      dark: oldWidget.brightness == ui.Brightness.dark,
    );
    if (old == _layer) return;
    final change = 'layer changed ${old.key} → ${_layer.key}';
    if (_running) {
      _stop(
        change,
        rebuild: false,
        what: 'holiday=${oldWidget.mood.name} layer=${old.key}',
      );
    }
    _blocked = null;
    _update(change);
  }

  @override
  void dispose() {
    if (_running) {
      _runTime.stop();
      _log.fine(
        'decor animation stopped $_what reason=card removed '
        'after ${_runTime.elapsedMilliseconds}ms',
      );
    }
    _position?.removeListener(_queueVisibilityCheck);
    _lifecycle.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _lifecycleChanged(AppLifecycleState state) {
    if (!mounted) return;
    _update('app ${state.name}', rebuild: true);
  }

  String? _blocker() {
    if (_disabled) return 'system animations disabled';
    if (!_tickers) return 'screen hidden (another tab or screen on top)';
    final state = WidgetsBinding.instance.lifecycleState;
    switch (state) {
      case null:
        return 'app lifecycle unknown';
      case AppLifecycleState.hidden ||
          AppLifecycleState.paused ||
          AppLifecycleState.detached:
        return 'app in background (${state.name})';
      case AppLifecycleState.resumed || AppLifecycleState.inactive:
        break;
    }
    if (!_onScreen) return 'card scrolled out of view';
    return null;
  }

  void _update(String trigger, {bool rebuild = false}) {
    final cycle = decorCycleOf(_layer);
    if (cycle == null) {
      if (_running) _stop('season decor is static', rebuild: rebuild);
      _blocked = null;
      return;
    }
    final blocker = _blocker();
    if (blocker == null) {
      if (!_running) _start(cycle, trigger, rebuild: rebuild);
    } else if (_running) {
      _stop(blocker, rebuild: rebuild);
    } else if (_blocked == null) {
      _log.fine(
        'decor animation not started $_what reason=$blocker '
        '→ static picture',
      );
    }
    _blocked = blocker;
  }

  void _start(Duration cycle, String trigger, {required bool rebuild}) {
    void apply() {
      _running = true;
      _opening = true;
    }

    rebuild ? setState(apply) : apply();
    _controller
      ..duration = cycle
      ..forward(from: 0);
    _runTime
      ..reset()
      ..start();
    _log.fine(
      'decor animation started $_what cycle=${cycle.inMilliseconds}ms '
      'trigger=$trigger',
    );
  }

  void _stop(String reason, {required bool rebuild, String? what}) {
    _controller.reset();
    void apply() {
      _running = false;
      _opening = true;
    }

    rebuild ? setState(apply) : apply();
    _runTime.stop();
    _log.fine(
      'decor animation paused ${what ?? _what} reason=$reason '
      'after ${_runTime.elapsedMilliseconds}ms',
    );
  }

  void _statusChanged(AnimationStatus status) {
    if (status != AnimationStatus.completed || !_running || !mounted) return;
    setState(() => _opening = false);
    _controller.repeat();
    _log.finer(
      'decor animation opening pass done $_what '
      'in ${_runTime.elapsedMilliseconds}ms → looping',
    );
  }

  void _queueVisibilityCheck() {
    if (_checkQueued || _scrollable == null) return;
    _checkQueued = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _checkQueued = false;
      if (!mounted) return;
      final visible = _visibleInScroll();
      if (visible == _onScreen) return;
      _onScreen = visible;
      _update(
        visible ? 'scrolled into view' : 'scrolled out of view',
        rebuild: true,
      );
    }, debugLabel: 'decor visibility');
  }

  bool _visibleInScroll() {
    final box = context.findRenderObject();
    final viewport = _scrollable?.context.findRenderObject();
    if (box is! RenderBox ||
        viewport is! RenderBox ||
        !box.attached ||
        !viewport.attached ||
        !box.hasSize ||
        !viewport.hasSize) {
      return true;
    }
    final rect = MatrixUtils.transformRect(
      box.getTransformTo(viewport),
      Offset.zero & box.size,
    );
    return rect.overlaps(Offset.zero & viewport.size);
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      willChange: _running,
      painter: DecorPainter(
        mood: widget.mood,
        brightness: widget.brightness,
        phase: widget.phase,
        cornerRadius: widget.cornerRadius,
        animation: _running ? _controller : null,
        opening: _opening,
      ),
    ),
  );
}

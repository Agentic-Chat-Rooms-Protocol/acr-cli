import 'dart:async';

/// Adaptive Dirty Gate TUI Rendering Loop
///
/// Implements high-density terminal rendering with dirty-gate skipping:
/// - Fast wake interval: 66ms (~15 FPS active response)
/// - Idle backoff interval: Up to 500ms (power-saving idle state)
/// - Clean frame skips when no state mutations are pending
/// - Zero emoji policy throughout.
class AdaptiveRenderLoop {
  static const Duration defaultMinInterval = Duration(milliseconds: 66);
  static const Duration defaultMaxInterval = Duration(milliseconds: 500);

  final Duration minInterval;
  final Duration maxInterval;
  final double backoffMultiplier;
  final void Function()? onRender;

  bool _isDirty = false;
  bool _isRunning = false;
  Duration _currentInterval;
  Timer? _timer;

  int _renderedFrames = 0;
  int _skippedFrames = 0;

  AdaptiveRenderLoop({
    this.minInterval = defaultMinInterval,
    this.maxInterval = defaultMaxInterval,
    this.backoffMultiplier = 1.5,
    this.onRender,
  }) : _currentInterval = minInterval;

  bool get isDirty => _isDirty;
  bool get isRunning => _isRunning;
  Duration get currentInterval => _currentInterval;
  int get renderedFrames => _renderedFrames;
  int get skippedFrames => _skippedFrames;
  int get totalCycles => _renderedFrames + _skippedFrames;

  double get cleanSkipRatio {
    if (totalCycles == 0) return 0.0;
    return _skippedFrames / totalCycles;
  }

  /// Marks the state as dirty, immediately waking or resetting interval to fast 66ms rate.
  void markDirty() {
    _isDirty = true;
    _currentInterval = minInterval;
  }

  /// Starts the asynchronous loop.
  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _scheduleNext();
  }

  /// Stops the loop and cancels any pending timers.
  void stop() {
    _isRunning = false;
    _timer?.cancel();
    _timer = null;
  }

  /// Executes a single discrete cycle for deterministic execution or unit tests.
  /// Returns true if a frame was rendered, false if skipped by the dirty gate.
  bool tick() {
    if (_isDirty) {
      _isDirty = false;
      _renderedFrames++;
      _currentInterval = minInterval;
      onRender?.call();
      return true;
    } else {
      _skippedFrames++;
      // Backoff interval up to maxInterval
      final nextMs = (_currentInterval.inMilliseconds * backoffMultiplier).round();
      if (nextMs >= maxInterval.inMilliseconds) {
        _currentInterval = maxInterval;
      } else {
        _currentInterval = Duration(milliseconds: nextMs);
      }
      return false;
    }
  }

  void _scheduleNext() {
    if (!_isRunning) return;
    _timer = Timer(_currentInterval, () {
      if (!_isRunning) return;
      tick();
      _scheduleNext();
    });
  }

  /// Telemetry metrics for HUD observability.
  Map<String, dynamic> getMetrics() {
    return {
      'is_running': _isRunning,
      'is_dirty': _isDirty,
      'rendered_frames': _renderedFrames,
      'skipped_frames': _skippedFrames,
      'total_cycles': totalCycles,
      'clean_skip_ratio': cleanSkipRatio,
      'current_interval_ms': _currentInterval.inMilliseconds,
      'min_interval_ms': minInterval.inMilliseconds,
      'max_interval_ms': maxInterval.inMilliseconds,
    };
  }
}

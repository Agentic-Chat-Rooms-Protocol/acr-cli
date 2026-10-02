import 'package:acr_cli/src/tui/render_loop.dart';
import 'package:test/test.dart';

void main() {
  group('AdaptiveRenderLoop Dirty Gate TUI Tests', () {
    test('Initializes with 66ms to 500ms interval bounds', () {
      final loop = AdaptiveRenderLoop();
      expect(loop.minInterval.inMilliseconds, equals(66));
      expect(loop.maxInterval.inMilliseconds, equals(500));
      expect(loop.currentInterval.inMilliseconds, equals(66));
      expect(loop.isDirty, isFalse);
      expect(loop.renderedFrames, equals(0));
      expect(loop.skippedFrames, equals(0));
      expect(loop.cleanSkipRatio, equals(0.0));
    });

    test('Skips rendering and backs off wake interval when state is clean', () {
      int renderCalls = 0;
      final loop = AdaptiveRenderLoop(
        onRender: () => renderCalls++,
      );

      // Cycle 1: Clean skip, interval backs off from 66 to 99ms
      expect(loop.tick(), isFalse);
      expect(renderCalls, equals(0));
      expect(loop.skippedFrames, equals(1));
      expect(loop.renderedFrames, equals(0));
      expect(loop.currentInterval.inMilliseconds, equals(99));

      // Cycle 2: Clean skip, interval backs off to 149ms
      expect(loop.tick(), isFalse);
      expect(loop.currentInterval.inMilliseconds, equals(149));

      // Cycle 3: Clean skip, interval backs off to 224ms
      expect(loop.tick(), isFalse);
      expect(loop.currentInterval.inMilliseconds, equals(224));

      // Multiple cycles to hit 500ms ceiling
      loop.tick(); // 336
      loop.tick(); // 500 max capped
      loop.tick(); // still 500
      expect(loop.currentInterval.inMilliseconds, equals(500));
    });

    test('Executes render and snaps back to 66ms when marked dirty', () {
      int renderCalls = 0;
      final loop = AdaptiveRenderLoop(
        onRender: () => renderCalls++,
      );

      // Backoff to 500ms
      for (int i = 0; i < 6; i++) {
        loop.tick();
      }
      expect(loop.currentInterval.inMilliseconds, equals(500));

      // Mark dirty
      loop.markDirty();
      expect(loop.isDirty, isTrue);
      expect(loop.currentInterval.inMilliseconds, equals(66));

      // Next tick renders
      expect(loop.tick(), isTrue);
      expect(renderCalls, equals(1));
      expect(loop.isDirty, isFalse);
      expect(loop.renderedFrames, equals(1));
      expect(loop.currentInterval.inMilliseconds, equals(66));
    });

    test('Accurately computes clean skip ratio and metrics', () {
      final loop = AdaptiveRenderLoop();

      // 4 clean skips, 1 dirty render
      loop.tick();
      loop.tick();
      loop.tick();
      loop.tick();
      loop.markDirty();
      loop.tick();

      expect(loop.totalCycles, equals(5));
      expect(loop.skippedFrames, equals(4));
      expect(loop.renderedFrames, equals(1));
      expect(loop.cleanSkipRatio, closeTo(0.8, 0.001));

      final metrics = loop.getMetrics();
      expect(metrics['total_cycles'], equals(5));
      expect(metrics['clean_skip_ratio'], closeTo(0.8, 0.001));
      expect(metrics['min_interval_ms'], equals(66));
      expect(metrics['max_interval_ms'], equals(500));
    });
  });
}

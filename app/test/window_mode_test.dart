import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/data/services/window_mode.dart';

/// Records what the window was asked to do, in order.
class _FakeEffects implements WindowModeEffects {
  final List<String> calls = <String>[];

  /// Lets a test hold a transition open and prove the next one queues behind
  /// it instead of interleaving.
  Completer<void>? gate;

  @override
  Future<void> applyMini() async {
    calls.add('mini');
    await gate?.future;
  }

  @override
  Future<void> applyExpanded() async {
    calls.add('expanded');
    await gate?.future;
  }

  @override
  Future<void> applyQuit() async => calls.add('quit');
}

void main() {
  late _FakeEffects effects;

  setUp(() => effects = _FakeEffects());

  WindowModeController controller({WindowMode initial = WindowMode.expanded}) =>
      WindowModeController(effects: effects, initial: initial);

  group('where the app starts', () {
    test('a paired, logged-in user gets the little window', () {
      expect(initialWindowMode(paired: true), WindowMode.mini);
    });

    test('onboarding gets the full panel — you cannot type into a card', () {
      expect(initialWindowMode(paired: false), WindowMode.expanded);
    });
  });

  group('transitions', () {
    test('collapse and expand drive both the mode and the window', () async {
      final c = controller();

      await c.collapse();
      expect(c.mode, WindowMode.mini);
      expect(c.isMini, isTrue);

      await c.expand();
      expect(c.mode, WindowMode.expanded);
      expect(effects.calls, ['mini', 'expanded']);
    });

    test('asking for the mode we are already in does nothing', () async {
      final c = controller(initial: WindowMode.mini);

      await c.collapse();
      await c.setMode(WindowMode.mini);

      expect(effects.calls, isEmpty);
    });

    test('toggle flips whichever way we are facing', () async {
      final c = controller(initial: WindowMode.mini);

      await c.toggle();
      expect(c.mode, WindowMode.expanded);
      await c.toggle();
      expect(c.mode, WindowMode.mini);
      expect(effects.calls, ['expanded', 'mini']);
    });

    test('listeners hear about the change', () async {
      final c = controller();
      var notifications = 0;
      c.addListener(() => notifications++);

      await c.collapse();
      await c.expand();

      expect(notifications, 2);
    });

    test('transitions run one at a time, never interleaved', () async {
      final c = controller();
      effects.gate = Completer<void>();

      final first = c.collapse();
      final second = c.expand();
      // Let the first transition start, then check the second is still
      // waiting rather than resizing the same window underneath it.
      await Future<void>.delayed(Duration.zero);
      expect(effects.calls, ['mini']);

      effects.gate!.complete();
      await Future.wait([first, second]);
      expect(effects.calls, ['mini', 'expanded']);
    });
  });

  group('closing collapses — it never quits', () {
    test('♥ on our title bar shrinks to the little window', () async {
      final c = controller();

      await c.closeToMini();

      expect(c.mode, WindowMode.mini);
      expect(c.isQuitting, isFalse);
      expect(effects.calls, ['mini']);
      expect(effects.calls, isNot(contains('quit')));
    });

    test(
      '★ collapses too — a tray app has no taskbar to minimize into',
      () async {
        final c = controller();

        await c.minimizeToMini();

        expect(c.mode, WindowMode.mini);
        expect(effects.calls, ['mini']);
        expect(effects.calls, isNot(contains('quit')));
      },
    );

    test('"quit for real" is the only way out', () async {
      final c = controller();

      await c.quit();

      expect(c.isQuitting, isTrue);
      expect(effects.calls, ['quit']);
    });

    test('quitting twice still only quits once', () async {
      final c = controller();

      await c.quit();
      await c.quit();

      expect(effects.calls, ['quit']);
    });

    test('a mode change after quitting is ignored', () async {
      final c = controller();

      await c.quit();
      await c.expand();

      expect(effects.calls, ['quit']);
    });
  });

  group('anchorResize keeps the window growing out of its own corner', () {
    const workArea = Rect.fromLTWH(0, 0, 1920, 1080);
    const mini = Size(240, 150);
    const panel = Size(400, 640);

    test('a card near the bottom-right grows up and to the left', () {
      // Docked bottom-right, 24px margin.
      const card = Rect.fromLTWH(1656, 906, 240, 150);

      final grown = anchorResize(from: card, to: panel, workArea: workArea);

      expect(grown.right, card.right);
      expect(grown.bottom, card.bottom);
      expect(grown.size, panel);
    });

    test('a card near the top-left grows down and to the right', () {
      const card = Rect.fromLTWH(20, 20, 240, 150);

      final grown = anchorResize(from: card, to: panel, workArea: workArea);

      expect(grown.left, card.left);
      expect(grown.top, card.top);
    });

    test('shrinking back re-uses the same corner', () {
      const panelRect = Rect.fromLTWH(1496, 416, 400, 640);

      final shrunk = anchorResize(
        from: panelRect,
        to: mini,
        workArea: workArea,
      );

      expect(shrunk.right, panelRect.right);
      expect(shrunk.bottom, panelRect.bottom);
      expect(shrunk.size, mini);
    });

    test('the result is clamped into the work area, never resized', () {
      // A card hugging the bottom edge of a short work area.
      const shortArea = Rect.fromLTWH(0, 0, 800, 600);
      const card = Rect.fromLTWH(700, 540, 240, 150);

      final grown = anchorResize(from: card, to: panel, workArea: shortArea);

      expect(grown.size, panel);
      expect(grown.left, 800 - 400);
      expect(grown.top, 600 - 640 < 0 ? 0 : 600 - 640);
      expect(grown.top, 0);
    });

    test('a work area offset from the origin is respected', () {
      // Second monitor to the right, with a taskbar-free top-left at 1920,0.
      const secondScreen = Rect.fromLTWH(1920, 0, 1920, 1040);
      const card = Rect.fromLTWH(1940, 20, 240, 150);

      final grown = anchorResize(from: card, to: panel, workArea: secondScreen);

      expect(grown.left, 1940);
      expect(grown.top, 20);
    });
  });
}

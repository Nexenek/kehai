import 'dart:math' as math;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/data/services/oled_care.dart';

/// A queue of fixed `nextDouble()` answers, so a test can dictate exactly
/// where each nudge lands instead of asserting only bounds. Wraps around —
/// handy for "same value every time" tests — and falls back to 0.5 (the
/// midpoint, i.e. no offset) once a short queue runs dry.
class _ScriptedRandom implements math.Random {
  _ScriptedRandom(this._answers);

  final List<double> _answers;
  int _i = 0;

  @override
  double nextDouble() {
    if (_answers.isEmpty) return 0.5;
    return _answers[_i++ % _answers.length];
  }

  @override
  bool nextBool() => false;

  @override
  int nextInt(int max) => 0;
}

void main() {
  const base = Offset(100, 200);

  ({List<Offset> moves, List<double> opacities}) recorder() =>
      (moves: <Offset>[], opacities: <double>[]);

  OledCare care({
    required List<Offset> moves,
    required List<double> opacities,
    math.Random? random,
  }) => OledCare(
    moveTo: (position) async => moves.add(position),
    setOpacity: (opacity) async => opacities.add(opacity),
    random: random,
  );

  group('the nudge walk', () {
    test('does nothing until start() is called', () {
      fakeAsync((async) {
        final rec = recorder();
        care(moves: rec.moves, opacities: rec.opacities);

        async.elapse(const Duration(minutes: 10));

        expect(rec.moves, isEmpty);
      });
    });

    test('nudges on the ~60s schedule, and only then', () {
      fakeAsync((async) {
        final rec = recorder();
        final c = care(moves: rec.moves, opacities: rec.opacities);

        c.start(base);
        expect(rec.moves, isEmpty);

        async.elapse(const Duration(seconds: 59));
        expect(rec.moves, isEmpty);

        async.elapse(const Duration(seconds: 1));
        expect(rec.moves, hasLength(1));

        async.elapse(OledCare.nudgeInterval * 3);
        expect(rec.moves, hasLength(4));
      });
    });

    test('every nudge stays within ±nudgeRange of base, on both axes', () {
      fakeAsync((async) {
        final rec = recorder();
        // A wide spread of random answers, including the extremes.
        final c = care(
          moves: rec.moves,
          opacities: rec.opacities,
          random: _ScriptedRandom([0.0, 1.0, 0.5, 0.0, 1.0, 1.0, 0.25, 0.75]),
        );

        c.start(base);
        async.elapse(OledCare.nudgeInterval * 4);

        expect(rec.moves, hasLength(4));
        for (final move in rec.moves) {
          expect(
            (move.dx - base.dx).abs(),
            lessThanOrEqualTo(OledCare.nudgeRange),
          );
          expect(
            (move.dy - base.dy).abs(),
            lessThanOrEqualTo(OledCare.nudgeRange),
          );
        }
      });
    });

    test('a fixed random answer reproduces the exact expected offset', () {
      fakeAsync((async) {
        final rec = recorder();
        // nextDouble() == 1.0 on both axes -> the max offset, +range/+range.
        final c = care(
          moves: rec.moves,
          opacities: rec.opacities,
          random: _ScriptedRandom([1.0, 1.0]),
        );

        c.start(base);
        async.elapse(OledCare.nudgeInterval);

        expect(
          rec.moves.single,
          Offset(base.dx + OledCare.nudgeRange, base.dy + OledCare.nudgeRange),
        );
      });
    });

    test(
      'a random walk that never drifts — every nudge is measured from '
      'base, not from the previous nudge',
      () {
        fakeAsync((async) {
          final rec = recorder();
          // Every nudge asks for the max +range/+range offset; if nudges
          // compounded from the previous position, the second and third
          // would land far outside nudgeRange of the original base.
          final c = care(
            moves: rec.moves,
            opacities: rec.opacities,
            random: _ScriptedRandom([1.0, 1.0]),
          );

          c.start(base);
          async.elapse(OledCare.nudgeInterval * 3);

          expect(rec.moves, hasLength(3));
          // All three land on exactly the same spot — base measured fresh
          // each time, never the last nudge.
          expect(rec.moves.toSet(), hasLength(1));
          expect(c.base, base);
        });
      },
    );
  });

  group('the user placing the window themselves', () {
    test('onUserMoved becomes the new base for future nudges', () {
      fakeAsync((async) {
        final rec = recorder();
        final c = care(
          moves: rec.moves,
          opacities: rec.opacities,
          random: _ScriptedRandom([1.0, 1.0]),
        );

        c.start(base);
        async.elapse(const Duration(seconds: 30));

        const dropped = Offset(500, 60);
        c.onUserMoved(dropped);
        expect(c.base, dropped);

        async.elapse(OledCare.nudgeInterval);
        expect(
          rec.moves.last,
          Offset(
            dropped.dx + OledCare.nudgeRange,
            dropped.dy + OledCare.nudgeRange,
          ),
        );
      });
    });

    test('onUserMoved while inactive just remembers the base, no timer', () {
      fakeAsync((async) {
        final rec = recorder();
        final c = care(moves: rec.moves, opacities: rec.opacities);

        c.onUserMoved(base);
        async.elapse(const Duration(minutes: 5));

        expect(c.base, base);
        expect(rec.moves, isEmpty);
      });
    });
  });

  group('idle dimming', () {
    test('dims to dimmedOpacity after idleDimDelay with no hover', () {
      fakeAsync((async) {
        final rec = recorder();
        final c = care(moves: rec.moves, opacities: rec.opacities);

        c.start(base);
        async.elapse(OledCare.idleDimDelay - const Duration(seconds: 1));
        expect(c.isDimmed, isFalse);
        expect(rec.opacities, isEmpty);

        async.elapse(const Duration(seconds: 1));
        expect(c.isDimmed, isTrue);
        expect(rec.opacities, [OledCare.dimmedOpacity]);
      });
    });

    test('hovering before the delay elapses cancels the dim entirely', () {
      fakeAsync((async) {
        final rec = recorder();
        final c = care(moves: rec.moves, opacities: rec.opacities);

        c.start(base);
        async.elapse(const Duration(seconds: 90));
        c.onHoverEnter();
        async.elapse(const Duration(minutes: 5));

        expect(c.isDimmed, isFalse);
        expect(rec.opacities, isEmpty);
      });
    });

    test('hovering after a dim undims immediately', () {
      fakeAsync((async) {
        final rec = recorder();
        final c = care(moves: rec.moves, opacities: rec.opacities);

        c.start(base);
        async.elapse(OledCare.idleDimDelay);
        expect(c.isDimmed, isTrue);

        c.onHoverEnter();
        expect(c.isDimmed, isFalse);
        expect(rec.opacities, [OledCare.dimmedOpacity, OledCare.fullOpacity]);
      });
    });

    test('leaving again after undimming restarts the countdown', () {
      fakeAsync((async) {
        final rec = recorder();
        final c = care(moves: rec.moves, opacities: rec.opacities);

        c.start(base);
        async.elapse(OledCare.idleDimDelay);
        c.onHoverEnter();
        rec.opacities.clear();

        c.onHoverExit();
        async.elapse(OledCare.idleDimDelay - const Duration(seconds: 1));
        expect(c.isDimmed, isFalse);

        async.elapse(const Duration(seconds: 1));
        expect(c.isDimmed, isTrue);
        expect(rec.opacities, [OledCare.dimmedOpacity]);
      });
    });

    test('dimming never blocks the nudge schedule running alongside it', () {
      fakeAsync((async) {
        final rec = recorder();
        final c = care(moves: rec.moves, opacities: rec.opacities);

        c.start(base);
        async.elapse(OledCare.idleDimDelay + OledCare.nudgeInterval);

        expect(c.isDimmed, isTrue);
        expect(rec.moves, isNotEmpty);
      });
    });
  });

  group('turning oled care off', () {
    test('disabled = snap back to base, and no more timers', () {
      fakeAsync((async) {
        final rec = recorder();
        final c = care(
          moves: rec.moves,
          opacities: rec.opacities,
          random: _ScriptedRandom([1.0, 1.0]),
        );

        c.start(base);
        async.elapse(OledCare.nudgeInterval); // wanders off base
        expect(rec.moves.last, isNot(base));

        c.stop(snapBack: true);
        expect(rec.moves.last, base);
        expect(c.isActive, isFalse);

        final movesBeforeWait = rec.moves.length;
        async.elapse(const Duration(hours: 1));
        expect(rec.moves, hasLength(movesBeforeWait)); // no further nudges
      });
    });

    test('disabling while dimmed restores full opacity', () {
      fakeAsync((async) {
        final rec = recorder();
        final c = care(moves: rec.moves, opacities: rec.opacities);

        c.start(base);
        async.elapse(OledCare.idleDimDelay);
        expect(c.isDimmed, isTrue);

        c.stop(snapBack: true);
        expect(c.isDimmed, isFalse);
        expect(rec.opacities.last, OledCare.fullOpacity);

        async.elapse(const Duration(hours: 1));
        // The idle timer is gone too — no further opacity changes.
        expect(rec.opacities.last, OledCare.fullOpacity);
      });
    });

    test('expanding (stop without snapBack) stops nudges but leaves the '
        'window where it is', () {
      fakeAsync((async) {
        final rec = recorder();
        final c = care(moves: rec.moves, opacities: rec.opacities);

        c.start(base);
        c.stop(); // panel opened — no snapBack

        expect(rec.moves, isEmpty); // never moved anywhere
        expect(c.isActive, isFalse);

        async.elapse(const Duration(hours: 1));
        expect(rec.moves, isEmpty); // still nothing — no nudges while paused
      });
    });

    test('stop() is safe with no base ever set', () {
      fakeAsync((async) {
        final rec = recorder();
        final c = care(moves: rec.moves, opacities: rec.opacities);

        expect(() => c.stop(snapBack: true), returnsNormally);
        expect(rec.moves, isEmpty);
      });
    });

    test('restarting after a pause resumes nudging around the new base', () {
      fakeAsync((async) {
        final rec = recorder();
        final c = care(moves: rec.moves, opacities: rec.opacities);

        c.start(base);
        c.stop(); // "expanded"
        async.elapse(const Duration(hours: 1));
        expect(rec.moves, isEmpty);

        const backToMini = Offset(10, 10);
        c.start(backToMini); // mini again, maybe at a new spot
        async.elapse(OledCare.nudgeInterval);

        expect(rec.moves, hasLength(1));
        expect((rec.moves.single - backToMini).dx.abs(),
            lessThanOrEqualTo(OledCare.nudgeRange));
      });
    });
  });
}

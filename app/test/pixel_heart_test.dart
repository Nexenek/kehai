import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/ui/core/widgets/pixel_heart.dart';

double _paintedScale(WidgetTester tester) {
  final painted = tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((cp) => cp.painter)
      .whereType<PixelHeartPainter>();
  return painted.single.beatScale;
}

Widget _wrap(Widget child, {bool disableAnimations = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: Scaffold(body: child),
  ),
);

void main() {
  group('heartBeatScale (pure curve)', () {
    test('rests at baseline at the top of the cycle', () {
      expect(heartBeatScale(0.0), 1.0);
    });

    test('is elevated at the "lub" peak', () {
      expect(heartBeatScale(0.10), closeTo(1.22, 0.001));
    });

    test('is elevated (smaller) at the "dub" peak', () {
      expect(heartBeatScale(0.28), closeTo(1.12, 0.001));
    });

    test('rests back at baseline for the back half of the cycle', () {
      expect(heartBeatScale(0.6), 1.0);
      expect(heartBeatScale(0.9), 1.0);
    });
  });

  group('buildHeartCells', () {
    test('paints a symmetric 7x7 heart with an ink outline', () {
      const fill = Color(0xFFB24D89);
      const outline = Color(0xFF362D3B);
      final cells = buildHeartCells(fill: fill, outline: outline);
      final size = heartPixelGrid.length;
      expect(cells.length, size * size);
      expect(cells.where((c) => c == fill).length, greaterThan(0));
      expect(cells.where((c) => c == outline).length, greaterThan(0));

      // Left/right symmetry of the fill shape.
      for (var y = 0; y < size; y++) {
        for (var x = 0; x < size; x++) {
          final left = cells[y * size + x] == fill;
          final right = cells[y * size + (size - 1 - x)] == fill;
          expect(left, right, reason: 'row $y not symmetric at col $x');
        }
      }
    });
  });

  group('PixelHeart widget', () {
    testWidgets('renders without error', (tester) async {
      await tester.pumpWidget(_wrap(const PixelHeart(bpm: 72)));
      expect(tester.takeException(), isNull);
      expect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is PixelHeartPainter,
        ),
        findsOneWidget,
      );
    });

    testWidgets('rests at baseline scale on the very first frame', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const PixelHeart(bpm: 60)));
      expect(_paintedScale(tester), 1.0);
    });

    testWidgets(
      'pulses and returns to baseline after exactly one full period '
      '(60000/bpm ms)',
      (tester) async {
        // bpm=120 -> period 500ms.
        await tester.pumpWidget(_wrap(const PixelHeart(bpm: 120)));
        expect(_paintedScale(tester), 1.0);

        await tester.pump(const Duration(milliseconds: 100));
        expect(_paintedScale(tester), greaterThan(1.0));

        // The remaining 400ms of the 500ms period.
        await tester.pump(const Duration(milliseconds: 400));
        expect(_paintedScale(tester), closeTo(1.0, 0.01));
      },
    );

    testWidgets('the period tracks bpm — a slower heart is still elevated '
        'at a point where a faster one has already rested', (tester) async {
      // bpm=60 -> period 1000ms: 100ms in is right at the "lub" peak.
      await tester.pumpWidget(_wrap(const PixelHeart(bpm: 60)));
      await tester.pump(const Duration(milliseconds: 100));
      final slowScale = _paintedScale(tester);

      // bpm=120 -> period 500ms: 100ms in is already past the "lub" bump.
      await tester.pumpWidget(_wrap(const PixelHeart(bpm: 120)));
      await tester.pump(const Duration(milliseconds: 100));
      final fastScale = _paintedScale(tester);

      expect(slowScale, greaterThan(fastScale));
      expect(slowScale, closeTo(1.22, 0.01));
    });

    testWidgets('reduced motion holds the heart perfectly still', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const PixelHeart(bpm: 72), disableAnimations: true),
      );
      expect(_paintedScale(tester), 1.0);

      await tester.pump(const Duration(milliseconds: 400));
      expect(_paintedScale(tester), 1.0);
      await tester.pump(const Duration(milliseconds: 400));
      expect(_paintedScale(tester), 1.0);
    });
  });
}

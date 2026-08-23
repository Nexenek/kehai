import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/ui/features/instants/instant_image_prep.dart';

void main() {
  group('isCaptionWithinLimit', () {
    test('empty caption is within limit', () {
      expect(isCaptionWithinLimit(''), isTrue);
    });

    test('exactly 140 chars is within limit', () {
      expect(isCaptionWithinLimit('a' * 140), isTrue);
    });

    test('141 chars is over the limit', () {
      expect(isCaptionWithinLimit('a' * 141), isFalse);
    });
  });

  group('decideDownscale', () {
    test('an image already within the cap needs no downscale', () {
      final decision = decideDownscale(1200, 800);
      expect(decision.needed, isFalse);
      expect(decision.targetWidth, 1200);
      expect(decision.targetHeight, 800);
    });

    test('exactly at the cap needs no downscale', () {
      final decision = decideDownscale(1600, 900);
      expect(decision.needed, isFalse);
    });

    test('a landscape photo over the cap scales width down to 1600', () {
      final decision = decideDownscale(3200, 1800);
      expect(decision.needed, isTrue);
      expect(decision.targetWidth, 1600);
      expect(decision.targetHeight, 900);
    });

    test('a portrait photo over the cap scales height down to 1600', () {
      final decision = decideDownscale(1800, 3200);
      expect(decision.needed, isTrue);
      expect(decision.targetHeight, 1600);
      expect(decision.targetWidth, 900);
    });

    test('aspect ratio is preserved for an odd-numbered source size', () {
      final decision = decideDownscale(4000, 3000, maxDimension: 1600);
      expect(decision.needed, isTrue);
      // 4000x3000 is 4:3 — target should stay 4:3 (1600x1200).
      expect(decision.targetWidth, 1600);
      expect(decision.targetHeight, 1200);
    });

    test(
      'a degenerate zero-size input is left alone rather than dividing by zero',
      () {
        final decision = decideDownscale(0, 0);
        expect(decision.needed, isFalse);
        expect(decision.targetWidth, 0);
        expect(decision.targetHeight, 0);
      },
    );
  });

  group('instantUploadFilename', () {
    test('downscaled images always upload as PNG', () {
      expect(instantUploadFilename(true, 'IMG_1234.HEIC'), 'instant.png');
    });

    test('untouched images keep their original name', () {
      expect(instantUploadFilename(false, 'IMG_1234.jpg'), 'IMG_1234.jpg');
    });

    test('an untouched image with no name falls back to a sane default', () {
      expect(instantUploadFilename(false, ''), 'instant.jpg');
    });
  });
}

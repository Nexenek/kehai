import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/ui/features/art/art_image_prep.dart';

/// A real, valid 1×1 transparent PNG.
final Uint8List _realPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8'
  'AAAAASUVORK5CYII=',
);

/// Just the 24 bytes [readPngSize] looks at — magic + the IHDR length/type/
/// width/height — with the dimensions we want. Enough to exercise the
/// header reader without hand-rolling a zlib stream and CRCs.
Uint8List _pngHeader(int width, int height) {
  final bytes = Uint8List(24)
    ..setRange(0, 8, _realPng.sublist(0, 8))
    ..setRange(8, 16, _realPng.sublist(8, 16));
  final view = ByteData.sublistView(bytes, 16, 24)
    ..setUint32(0, width)
    ..setUint32(4, height);
  return Uint8List.sublistView(view.buffer.asUint8List());
}

Uint8List _jpegish() =>
    Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 16, 74, 70, 73, 70]);

void main() {
  group('PNG sniffing', () {
    test('recognises a real PNG by its magic bytes', () {
      expect(isPngBytes(_realPng), isTrue);
      expect(checkArtUpload(_realPng), isNull);
    });

    test('a JPEG is refused however it is named', () {
      expect(isPngBytes(_jpegish()), isFalse);
      expect(checkArtUpload(_jpegish()), ArtUploadProblem.notPng);
    });

    test('short and empty files are refused rather than crashing', () {
      expect(isPngBytes(Uint8List(0)), isFalse);
      expect(isPngBytes(Uint8List.fromList([0x89, 0x50])), isFalse);
      expect(checkArtUpload(Uint8List(0)), ArtUploadProblem.empty);
      expect(
        checkArtUpload(Uint8List.fromList([0x89, 0x50])),
        ArtUploadProblem.notPng,
      );
    });

    test('a PNG over the server ceiling is refused before it is sent', () {
      final big = Uint8List(artMaxUploadBytes + 1)
        ..setRange(0, 8, _realPng.sublist(0, 8));
      expect(checkArtUpload(big), ArtUploadProblem.tooBig);

      final justUnder = Uint8List(artMaxUploadBytes)
        ..setRange(0, 8, _realPng.sublist(0, 8));
      expect(checkArtUpload(justUnder), isNull);
    });
  });

  group('readPngSize', () {
    test('reads the IHDR dimensions', () {
      expect(readPngSize(_realPng), const PngSize(1, 1));
      expect(readPngSize(_pngHeader(512, 512)), const PngSize(512, 512));
      expect(readPngSize(_pngHeader(640, 480)), const PngSize(640, 480));
    });

    test('knows a square from a rectangle', () {
      expect(readPngSize(_pngHeader(512, 512))!.isSquare, isTrue);
      expect(readPngSize(_pngHeader(640, 480))!.isSquare, isFalse);
      expect(readPngSize(_pngHeader(512, 512)).toString(), '512x512');
    });

    test('returns null rather than throwing on anything that is not a '
        'readable PNG header', () {
      expect(readPngSize(_jpegish()), isNull);
      expect(readPngSize(Uint8List(0)), isNull);
      expect(readPngSize(_realPng.sublist(0, 20)), isNull);
      expect(readPngSize(_pngHeader(0, 512)), isNull);
    });
  });

  group('artUploadFilename', () {
    test('keeps a sensible .png name', () {
      expect(artUploadFilename('base', 'sleepy.png'), 'sleepy.png');
      expect(artUploadFilename('base', 'Sleepy.PNG'), 'Sleepy.PNG');
    });

    test('falls back to the slot name when the picker gives nothing '
        'useful', () {
      expect(artUploadFilename('outfit', ''), 'outfit.png');
      expect(artUploadFilename('outfit', 'photo.jpg'), 'outfit.png');
      expect(artUploadFilename('prop', '.png'), 'prop.png');
    });
  });
}

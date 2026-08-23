import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/ui/features/files/file_type_glyph.dart';

void main() {
  group('sharedFileGlyph', () {
    test('images get the ◉ glyph', () {
      for (final ext in ['jpg', 'JPEG', 'png', 'gif', 'webp', 'heic']) {
        expect(sharedFileGlyph(ext.toLowerCase()), '◉', reason: ext);
      }
    });

    test('audio gets the ♪ glyph', () {
      for (final ext in ['mp3', 'wav', 'flac', 'ogg', 'm4a']) {
        expect(sharedFileGlyph(ext), '♪', reason: ext);
      }
    });

    test('video gets the ▸ glyph', () {
      for (final ext in ['mp4', 'mov', 'mkv', 'webm']) {
        expect(sharedFileGlyph(ext), '▸', reason: ext);
      }
    });

    test('documents get the ✎ glyph', () {
      for (final ext in ['pdf', 'doc', 'docx', 'txt', 'md', 'xlsx', 'csv']) {
        expect(sharedFileGlyph(ext), '✎', reason: ext);
      }
    });

    test('anything unrecognized (including empty) gets the ▪ glyph', () {
      for (final ext in ['zip', 'exe', 'bin', 'apk', '']) {
        expect(sharedFileGlyph(ext), '▪', reason: ext);
      }
    });
  });
}

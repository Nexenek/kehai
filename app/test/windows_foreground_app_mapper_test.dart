import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/data/services/presence/windows_foreground_app_mapper.dart';

void main() {
  group('WindowsForegroundAppMapper.map', () {
    test('maps a well-formed {exe, title} result', () {
      final result = WindowsForegroundAppMapper.map({
        'exe': 'spotify',
        'title': 'Marigold - yeule',
      });

      expect(result, isNotNull);
      expect(result!.exe, 'spotify');
      expect(result.title, 'Marigold - yeule');
    });

    test('null result (no foreground window / access denied) maps to null', () {
      expect(WindowsForegroundAppMapper.map(null), isNull);
    });

    test('a non-map result maps to null', () {
      expect(WindowsForegroundAppMapper.map('unexpected'), isNull);
    });

    test('missing exe maps to null', () {
      final result = WindowsForegroundAppMapper.map({'title': 'Untitled'});
      expect(result, isNull);
    });

    test('empty-string exe maps to null', () {
      final result = WindowsForegroundAppMapper.map({
        'exe': '',
        'title': 'Untitled',
      });
      expect(result, isNull);
    });

    test('missing title is treated as an empty title, not a null result', () {
      final result = WindowsForegroundAppMapper.map({'exe': 'explorer'});
      expect(result, isNotNull);
      expect(result!.exe, 'explorer');
      expect(result.title, '');
    });

    test('null title is treated as an empty title', () {
      final result = WindowsForegroundAppMapper.map({
        'exe': 'explorer',
        'title': null,
      });
      expect(result, isNotNull);
      expect(result!.title, '');
    });

    test('a StandardMethodCodec-decoded Map<Object?, Object?> is accepted', () {
      // MethodChannel decodes a StandardMethodCodec map with dynamic key
      // and value types, not Map<String, dynamic> — make sure the mapper
      // doesn't assume a narrower map type than what actually arrives.
      final Map<Object?, Object?> raw = {
        'exe': 'chrome',
        'title': 'Kehai - Google Chrome',
      };
      final result = WindowsForegroundAppMapper.map(raw);
      expect(result, isNotNull);
      expect(result!.exe, 'chrome');
      expect(result.title, 'Kehai - Google Chrome');
    });
  });
}

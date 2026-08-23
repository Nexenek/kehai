import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/ui/features/files/shared_file_upload_limits.dart';

void main() {
  group('isWithinSharedFileUploadLimit', () {
    test('accepts a small file', () {
      expect(isWithinSharedFileUploadLimit(1024), isTrue);
    });

    test('accepts exactly the cap', () {
      expect(
        isWithinSharedFileUploadLimit(sharedFileMaxUploadBytes),
        isTrue,
      );
    });

    test('rejects one byte over the cap', () {
      expect(
        isWithinSharedFileUploadLimit(sharedFileMaxUploadBytes + 1),
        isFalse,
      );
    });

    test('the cap matches the server (server/migrations/12_files.go)', () {
      expect(sharedFileMaxUploadBytes, 100 * 1024 * 1024);
    });
  });
}

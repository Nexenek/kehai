import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/app_controller.dart';

void main() {
  group('AppController.serverCandidates', () {
    test('a bare hostname tries https first, then http', () {
      expect(AppController.serverCandidates('kehai.tail1234.ts.net'), [
        'https://kehai.tail1234.ts.net',
        'http://kehai.tail1234.ts.net',
      ]);
    });

    test('a bare host:port keeps the port on both attempts', () {
      expect(AppController.serverCandidates('100.1.2.3:8090'), [
        'https://100.1.2.3:8090',
        'http://100.1.2.3:8090',
      ]);
    });

    test('an explicit scheme is taken literally', () {
      expect(AppController.serverCandidates('http://100.1.2.3:8090'), [
        'http://100.1.2.3:8090',
      ]);
    });

    test('trailing slashes and whitespace are trimmed', () {
      expect(AppController.serverCandidates('  https://kehai.example/// '), [
        'https://kehai.example',
      ]);
    });

    test('empty input yields no candidates', () {
      expect(AppController.serverCandidates('   '), isEmpty);
    });
  });
}

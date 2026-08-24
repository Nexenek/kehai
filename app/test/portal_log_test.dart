import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/data/services/portal/portal_log.dart';

/// Captures what actually reaches `debugPrint` — the only way to catch a
/// message that is built correctly and then printed wrong.
List<String> _capture(void Function() body) {
  final lines = <String>[];
  final original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) lines.add(message);
  };
  try {
    body();
  } finally {
    debugPrint = original;
  }
  return lines;
}

/// A real candidate line, of the shape libwebrtc emits. The address in it
/// is the whole reason [portalCandidateType] exists: none of it may reach a
/// log the user is going to paste somewhere.
const _host =
    'candidate:842163049 1 udp 2122260223 192.168.1.42 55555 typ host '
    'generation 0 ufrag k9Xz network-id 1 network-cost 10';
const _srflx =
    'candidate:842163049 1 udp 1686052607 203.0.113.7 55555 typ srflx '
    'raddr 192.168.1.42 rport 55555 generation 0';
const _relay =
    'candidate:2 1 udp 41885439 198.51.100.3 3478 typ relay '
    'raddr 203.0.113.7 rport 55555 generation 0';

void main() {
  group('what actually gets printed', () {
    test('portalLog prints the message under the prefix', () {
      final lines = _capture(() => portalLog('connecting → connected'));
      expect(lines, ['[KehaiPortal] connecting → connected']);
    });

    test('portalTrace calls its closure instead of printing it', () {
      // The shipped bug: `'$_prefix $message'` on a `String Function()`
      // compiles fine and prints `Closure: () => String`, so every trace
      // line in the first on-device capture was useless.
      final lines = _capture(() => portalTrace(() => 'local candidate host'));

      expect(lines, ['[KehaiPortal] local candidate host']);
      expect(lines.single, isNot(contains('Closure')));
      expect(lines.single, isNot(contains('=>')));
    });

    test('no log line ever prints a closure', () {
      final lines = _capture(() {
        portalLog('peer connection: failed');
        portalTrace(() => 'remote candidate srflx 0badc0de');
      });
      for (final line in lines) {
        expect(line, isNot(contains('Closure')));
      }
    });
  });

  group('portalCandidateType', () {
    test('reads the typ field of each candidate flavour', () {
      expect(portalCandidateType(_host), 'host');
      expect(portalCandidateType(_srflx), 'srflx');
      expect(portalCandidateType(_relay), 'relay');
    });

    test('an empty candidate is the end-of-gathering sentinel', () {
      expect(portalCandidateType(''), 'end-of-candidates');
      expect(portalCandidateType(null), 'end-of-candidates');
    });

    test('something unparseable degrades instead of throwing', () {
      expect(portalCandidateType('not a candidate at all'), '?');
    });

    test('it never yields anything that could be an address', () {
      for (final candidate in [_host, _srflx, _relay]) {
        final type = portalCandidateType(candidate);
        expect(type, matches(r'^[a-z]+$'));
        expect(type, isNot(contains('.')));
      }
    });
  });

  group('portalCandidateFingerprint', () {
    test('is stable, short, and reveals no address', () {
      final print = portalCandidateFingerprint(_host);
      expect(print, portalCandidateFingerprint(_host));
      expect(print, hasLength(8));
      expect(print, matches(r'^[0-9a-f]{8}$'));
      expect(_host, contains('192.168.1.42'));
      expect(print, isNot(contains('192')));
    });

    test('different candidates fingerprint differently', () {
      expect(
        portalCandidateFingerprint(_host),
        isNot(portalCandidateFingerprint(_srflx)),
      );
    });

    test('an empty candidate gets a placeholder, not a crash', () {
      expect(portalCandidateFingerprint(null), '--------');
      expect(portalCandidateFingerprint(''), '--------');
    });
  });
}

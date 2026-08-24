import 'package:clock/clock.dart';
import 'package:couples_app/data/services/presence/android/vitals_channel.dart';
import 'package:couples_app/data/services/presence/android/vitals_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [VitalsChannel] whose answers the test sets by hand, counting reads so
/// the 5-minute cadence is observable. Nothing here touches a
/// MethodChannel — the real one is a four-line wrapper, and the logic worth
/// testing is all in [VitalsService].
class _FakeVitalsChannel implements VitalsChannel {
  _FakeVitalsChannel({this.reading = VitalsReading.empty});

  VitalsReading reading;
  int reads = 0;

  @override
  Future<VitalsReading> read() async {
    reads++;
    return reading;
  }

  @override
  Future<VitalsAvailability> availability() async =>
      VitalsAvailability.available;

  @override
  Future<bool> hasPermissions() async => true;

  @override
  Future<bool> hasBackgroundPermission() async => true;

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<bool> openSettings() async => true;
}

/// A fixed "now" every test runs against — real [DateTime.now] would make
/// the freshness and cadence assertions below flaky by definition.
final _now = DateTime.utc(2026, 8, 24, 12, 0);

VitalsService _service(
  _FakeVitalsChannel channel, {
  bool enabled = true,
  bool isSupported = true,
}) =>
    VitalsService(
      channel: channel,
      isSupported: isSupported,
      // Pinned rather than defaulted: these tests assert cadence
      // *semantics* (cache reuse, expiry), and the default interval is a
      // product decision that has already changed once (5 → 2 minutes).
      refreshInterval: const Duration(minutes: 5),
    )..enabled = enabled;

void main() {
  group('VitalsService — the off switch', () {
    test('a non-Android platform never touches the channel', () async {
      final channel = _FakeVitalsChannel(
        reading: VitalsReading(stepsToday: 4231, bpm: 72, bpmAt: _now),
      );
      final service = _service(channel, isSupported: false);

      await withClock(Clock.fixed(_now), () async {
        expect(await service.telemetry(), isNull);
      });
      expect(channel.reads, 0);
    });

    test('shareVitals off means no channel call and no keys', () async {
      final channel = _FakeVitalsChannel(
        reading: VitalsReading(stepsToday: 4231, bpm: 72, bpmAt: _now),
      );
      final service = _service(channel, enabled: false);

      await withClock(Clock.fixed(_now), () async {
        expect(await service.telemetry(), isNull);
      });
      expect(channel.reads, 0);
    });

    test(
      'turning it off after sharing clears both keys exactly once',
      () async {
        final channel = _FakeVitalsChannel(
          reading: VitalsReading(stepsToday: 4231, bpm: 72, bpmAt: _now),
        );
        final service = _service(channel);

        await withClock(Clock.fixed(_now), () async {
          expect(await service.telemetry(), isNotNull);

          service.enabled = false;
          final clearing = await service.telemetry();
          expect(clearing, isNotNull);
          expect(clearing!.containsKey('steps_today'), isTrue);
          expect(clearing['steps_today'], isNull);
          expect(clearing.containsKey('heart_rate'), isTrue);
          expect(clearing['heart_rate'], isNull);

          // ...and then silence: the partner's card is already clear, so
          // every later heartbeat leaves the keys out entirely.
          expect(await service.telemetry(), isNull);
          expect(await service.telemetry(), isNull);
        });
        expect(channel.reads, 1);
      },
    );

    test('never having shared means "off" has nothing to clear', () async {
      final service = _service(_FakeVitalsChannel(), enabled: false);
      await withClock(Clock.fixed(_now), () async {
        expect(await service.telemetry(), isNull);
      });
    });
  });

  group('VitalsService — key omission', () {
    test('steps and a fresh sample both ride the heartbeat', () async {
      final measuredAt = _now.subtract(const Duration(minutes: 8));
      final service = _service(
        _FakeVitalsChannel(
          reading: VitalsReading(stepsToday: 4231, bpm: 72, bpmAt: measuredAt),
        ),
      );

      await withClock(Clock.fixed(_now), () async {
        final fields = (await service.telemetry())!;
        expect(fields['steps_today'], 4231);
        expect(fields['heart_rate'], {
          'bpm': 72,
          // The measured-at, not the read-at: that gap is the whole point
          // of carrying a timestamp.
          'at': measuredAt.toIso8601String(),
        });
      });
    });

    test('no reading at all writes no keys', () async {
      final service = _service(_FakeVitalsChannel());
      await withClock(Clock.fixed(_now), () async {
        expect(await service.telemetry(), isNull);
      });
    });

    test('steps with no watch sample omits heart_rate entirely', () async {
      final service = _service(
        _FakeVitalsChannel(reading: const VitalsReading(stepsToday: 512)),
      );
      await withClock(Clock.fixed(_now), () async {
        final fields = (await service.telemetry())!;
        expect(fields['steps_today'], 512);
        expect(fields.containsKey('heart_rate'), isFalse);
      });
    });

    test('a sample already older than 2h is never sent', () async {
      final service = _service(
        _FakeVitalsChannel(
          reading: VitalsReading(
            bpm: 64,
            bpmAt: _now.subtract(const Duration(hours: 3)),
          ),
        ),
      );
      await withClock(Clock.fixed(_now), () async {
        expect(await service.telemetry(), isNull);
      });
    });

    test('an out-of-contract bpm is dropped rather than clamped — a 400 '
        'would take every other telemetry key down with it', () async {
      final service = _service(
        _FakeVitalsChannel(
          reading: VitalsReading(stepsToday: 100, bpm: 400, bpmAt: _now),
        ),
      );
      await withClock(Clock.fixed(_now), () async {
        final fields = (await service.telemetry())!;
        expect(fields.containsKey('heart_rate'), isFalse);
        expect(fields['steps_today'], 100);
      });
    });

    test('an out-of-contract step count is dropped too', () async {
      final service = _service(
        _FakeVitalsChannel(reading: const VitalsReading(stepsToday: 999999)),
      );
      await withClock(Clock.fixed(_now), () async {
        expect(await service.telemetry(), isNull);
      });
    });
  });

  group('VitalsService — ageing a sample out', () {
    test('a previously-sent sample that ages past 2h is cleared with one '
        'explicit null, then left alone', () async {
      final measuredAt = _now.subtract(const Duration(minutes: 30));
      final channel = _FakeVitalsChannel(
        reading: VitalsReading(stepsToday: 4231, bpm: 72, bpmAt: measuredAt),
      );
      final service = _service(channel);

      await withClock(Clock.fixed(_now), () async {
        expect((await service.telemetry())!['heart_rate'], isNotNull);
      });

      // Two hours later the watch has synced nothing new, so the native
      // side's own 2h window returns no sample at all.
      final later = _now.add(const Duration(hours: 2));
      channel.reading = const VitalsReading(stepsToday: 6100);

      await withClock(Clock.fixed(later), () async {
        final cleared = (await service.telemetry())!;
        expect(cleared.containsKey('heart_rate'), isTrue);
        expect(cleared['heart_rate'], isNull);
        expect(cleared['steps_today'], 6100);

        // Next heartbeat: nothing left to clear, so the key goes away.
        final after = (await service.telemetry())!;
        expect(after.containsKey('heart_rate'), isFalse);
        expect(after['steps_today'], 6100);
      });
    });

    test('a cached sample ageing past 2h between reads is caught in Dart, '
        'not only by the native window', () async {
      final channel = _FakeVitalsChannel(
        reading: VitalsReading(
          bpm: 72,
          bpmAt: _now.subtract(const Duration(hours: 1, minutes: 59)),
        ),
      );
      final service = _service(channel);

      await withClock(Clock.fixed(_now), () async {
        expect((await service.telemetry())!['heart_rate'], isNotNull);
      });

      // Only two minutes on: still inside the 5-minute cache, so the same
      // reading comes back — but it's over the line now.
      await withClock(
        Clock.fixed(_now.add(const Duration(minutes: 2))),
        () async {
          final fields = (await service.telemetry())!;
          expect(fields.containsKey('heart_rate'), isTrue);
          expect(fields['heart_rate'], isNull);
        },
      );
      expect(channel.reads, 1);
    });
  });

  group('VitalsService — cadence', () {
    test('heartbeats inside the refresh window reuse one reading', () async {
      final channel = _FakeVitalsChannel(
        reading: const VitalsReading(stepsToday: 4231),
      );
      final service = _service(channel);

      // Ten heartbeats at the real 30s cadence — under five minutes.
      for (var i = 0; i < 10; i++) {
        await withClock(
          Clock.fixed(_now.add(Duration(seconds: 30 * i))),
          () async {
            expect((await service.telemetry())!['steps_today'], 4231);
          },
        );
      }

      expect(channel.reads, 1);
    });

    test('the first heartbeat past the window reads again', () async {
      final channel = _FakeVitalsChannel(
        reading: const VitalsReading(stepsToday: 4231),
      );
      final service = _service(channel);

      await withClock(Clock.fixed(_now), () async {
        await service.telemetry();
      });
      await withClock(
        Clock.fixed(_now.add(const Duration(minutes: 5))),
        () async {
          channel.reading = const VitalsReading(stepsToday: 5000);
          expect((await service.telemetry())!['steps_today'], 5000);
        },
      );

      expect(channel.reads, 2);
    });

    test('turning the opt-in off and on again drops the cache — an old '
        'reading must not survive the switch', () async {
      final channel = _FakeVitalsChannel(
        reading: const VitalsReading(stepsToday: 4231),
      );
      final service = _service(channel);

      await withClock(Clock.fixed(_now), () async {
        await service.telemetry();
        service.enabled = false;
        await service.telemetry(); // the clearing heartbeat
        service.enabled = true;
        await service.telemetry();
      });

      expect(channel.reads, 2);
    });
  });

  /// The degraded mode that has to still feel alive: without
  /// READ_HEALTH_DATA_IN_BACKGROUND every read from the backgrounded service
  /// comes back all-null, so the cached "nothing" would sit there for five
  /// minutes even though the app being opened is exactly the moment a read
  /// would finally work.
  group('VitalsService — invalidateCache', () {
    test(
      'the next telemetry reads again instead of reusing the cache',
      () async {
        final channel = _FakeVitalsChannel(
          reading: const VitalsReading(stepsToday: 4231),
        );
        final service = _service(channel);

        await withClock(Clock.fixed(_now), () async {
          await service.telemetry();
          // Same instant, so the cadence alone would never re-read.
          await service.telemetry();
          expect(channel.reads, 1);

          service.invalidateCache();
          channel.reading = const VitalsReading(stepsToday: 5117);
          expect((await service.telemetry())!['steps_today'], 5117);
        });

        expect(channel.reads, 2);
      },
    );

    test('a cache of nulls (the backgrounded-read failure) is replaced by a '
        'real reading the moment the app is opened', () async {
      // What a background read without the grant actually returns.
      final channel = _FakeVitalsChannel(reading: VitalsReading.empty);
      final service = _service(channel);

      await withClock(Clock.fixed(_now), () async {
        expect(await service.telemetry(), isNull);

        // App comes to the foreground: cache dropped, and now the read works.
        service.invalidateCache();
        channel.reading = VitalsReading(
          stepsToday: 4231,
          bpm: 72,
          bpmAt: _now.subtract(const Duration(minutes: 4)),
        );

        final fields = (await service.telemetry())!;
        expect(fields['steps_today'], 4231);
        expect(fields['heart_rate'], isNotNull);
      });
    });

    test(
      'invalidating while the opt-in is off still costs no channel call',
      () async {
        final channel = _FakeVitalsChannel(
          reading: const VitalsReading(stepsToday: 4231),
        );
        final service = _service(channel, enabled: false);

        await withClock(Clock.fixed(_now), () async {
          service.invalidateCache();
          expect(await service.telemetry(), isNull);
        });
        expect(channel.reads, 0);
      },
    );
  });

  group('VitalsReading.fromChannel', () {
    test('parses the native map', () {
      final reading = VitalsReading.fromChannel({
        'stepsToday': 4231,
        'bpm': 72.0,
        'bpmAt': '2026-08-24T11:52:00Z',
      });
      expect(reading.stepsToday, 4231);
      expect(reading.bpm, 72);
      expect(reading.bpmAt, DateTime.utc(2026, 8, 24, 11, 52));
      expect(reading.isEmpty, isFalse);
    });

    test('an all-null map is empty, not an exception', () {
      final reading = VitalsReading.fromChannel({
        'stepsToday': null,
        'bpm': null,
        'bpmAt': null,
      });
      expect(reading.isEmpty, isTrue);
    });

    test('a bpm with an unreadable timestamp is dropped whole — the '
        'contract needs both halves', () {
      final reading = VitalsReading.fromChannel({'bpm': 72.0, 'bpmAt': 'soon'});
      expect(reading.bpm, isNull);
      expect(reading.bpmAt, isNull);
    });

    test('a missing channel answer (null) is empty', () {
      expect(VitalsReading.fromChannel(null).isEmpty, isTrue);
    });
  });
}

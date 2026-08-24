import 'dart:async';

import 'package:couples_app/data/repositories/device_repository.dart';
import 'package:couples_app/data/services/device_info_service.dart';
import 'package:couples_app/data/services/heartbeat_service.dart';
import 'package:couples_app/data/services/presence/presence_service.dart';
import 'package:couples_app/domain/models/now_playing.dart';
import 'package:couples_app/domain/models/partner_status.dart';
import 'package:couples_app/domain/models/utc_offset.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase/pocketbase.dart';

/// Records the `extra` map of every heartbeat instead of posting it. The
/// PocketBase instance is never used — [sendHeartbeat] is fully overridden
/// — it just satisfies the superclass constructor.
class _RecordingDeviceRepository extends DeviceRepository {
  _RecordingDeviceRepository() : super(PocketBase('http://127.0.0.1:1'));

  final sent = <Map<String, dynamic>>[];

  @override
  Future<void> sendHeartbeat({
    required SourceKind kind,
    required String name,
    Map<String, dynamic> extra = const {},
  }) async {
    sent.add(Map<String, dynamic>.from(extra));
  }
}

/// Avoids device_info_plus (and therefore any platform channel) in tests.
class _FakeDeviceInfoService implements DeviceInfoService {
  const _FakeDeviceInfoService();

  @override
  SourceKind get kind => SourceKind.phone;

  @override
  Future<String> get deviceName async => 'test phone';
}

/// A [PresenceService] whose readings the test drives by hand.
class _FakePresenceService implements PresenceService {
  final _controller = StreamController<DevicePresence>.broadcast();
  DevicePresence _current = DevicePresence.empty;

  void emit(DevicePresence presence) {
    _current = presence;
    _controller.add(presence);
  }

  @override
  DevicePresence get current => _current;

  @override
  Stream<DevicePresence> get onChange => _controller.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> dispose() async => _controller.close();
}

void main() {
  late _RecordingDeviceRepository repository;
  late _FakePresenceService presence;
  late HeartbeatService heartbeat;

  setUp(() {
    repository = _RecordingDeviceRepository();
    presence = _FakePresenceService();
    heartbeat = HeartbeatService(
      repository,
      const _FakeDeviceInfoService(),
      presenceService: presence,
    );
  });

  tearDown(() {
    heartbeat.stop();
    presence.dispose();
  });

  test('a desktop-shaped reading writes no battery/charging keys', () async {
    presence.emit(const DevicePresence(idleSeconds: 12));
    await heartbeat.pingNow();

    expect(repository.sent.single.containsKey('battery'), isFalse);
    expect(repository.sent.single.containsKey('charging'), isFalse);
    expect(repository.sent.single['idle_seconds'], 12);
  });

  test('a phone reading carries battery and charging', () async {
    presence.emit(
      const DevicePresence(idleSeconds: 0, battery: 62, charging: true),
    );
    await heartbeat.pingNow();

    expect(repository.sent.single['battery'], 62);
    expect(repository.sent.single['charging'], isTrue);
  });

  test('a signal that goes away is cleared with an explicit null', () async {
    presence.emit(const DevicePresence(battery: 62, charging: true));
    await heartbeat.pingNow();

    presence.emit(DevicePresence.empty);
    await heartbeat.pingNow();

    final second = repository.sent.last;
    expect(second.containsKey('battery'), isTrue);
    expect(second['battery'], isNull);
    expect(second.containsKey('charging'), isTrue);
    expect(second['charging'], isNull);
  });

  test('plugging in triggers an out-of-band heartbeat', () async {
    heartbeat.start();
    await pumpEventQueue();
    final beforeCount = repository.sent.length;

    presence.emit(const DevicePresence(battery: 62, charging: true));
    await pumpEventQueue();

    expect(repository.sent.length, greaterThan(beforeCount));
    expect(repository.sent.last['charging'], isTrue);
  });

  test('a battery level ticking down alone does not', () async {
    heartbeat.start();
    presence.emit(const DevicePresence(battery: 62, charging: false));
    await pumpEventQueue();
    final beforeCount = repository.sent.length;

    presence.emit(const DevicePresence(battery: 61, charging: false));
    await pumpEventQueue();

    expect(repository.sent.length, beforeCount);
  });

  test('an activity reading is sent under the activity key', () async {
    presence.emit(
      const DevicePresence(idleSeconds: 0, activity: 'coding ⌨\uFE0E'),
    );
    await heartbeat.pingNow();

    expect(repository.sent.single['activity'], 'coding ⌨\uFE0E');
  });

  test('no activity signal at all writes no activity key', () async {
    presence.emit(const DevicePresence(idleSeconds: 0));
    await heartbeat.pingNow();

    expect(repository.sent.single.containsKey('activity'), isFalse);
  });

  test('activity going away (opt-in turned off) is cleared with an explicit '
      'null, mirroring now_playing', () async {
    presence.emit(const DevicePresence(activity: 'gaming'));
    await heartbeat.pingNow();

    presence.emit(DevicePresence.empty);
    await heartbeat.pingNow();

    final second = repository.sent.last;
    expect(second.containsKey('activity'), isTrue);
    expect(second['activity'], isNull);
  });

  test('activity alone changing does not trigger an out-of-band heartbeat '
      '(alt-tabbing would otherwise spam beats)', () async {
    heartbeat.start();
    presence.emit(const DevicePresence(activity: 'coding ⌨\uFE0E'));
    await pumpEventQueue();
    final beforeCount = repository.sent.length;

    presence.emit(const DevicePresence(activity: 'gaming'));
    await pumpEventQueue();

    expect(repository.sent.length, beforeCount);
  });

  // --- timezone (dual clocks, kb/features.md) --------------------------

  test('every heartbeat carries the device\'s current UTC offset', () async {
    presence.emit(DevicePresence.empty);
    await heartbeat.pingNow();

    expect(repository.sent.single['timezone'], UtcOffset.now().encode());
  });

  test('timezone is still sent when no presence signal is available '
      '(unlike battery/charging/activity, it is never opt-in)', () async {
    await heartbeat.pingNow();

    expect(repository.sent.single.containsKey('timezone'), isTrue);
    expect(repository.sent.single['timezone'], isNotNull);
  });

  // --- extraTelemetry (smartwatch vitals ride here) --------------------

  test('extraTelemetry keys are merged into the heartbeat body', () async {
    final heartbeatWithVitals = HeartbeatService(
      repository,
      const _FakeDeviceInfoService(),
      presenceService: presence,
      extraTelemetry: () async => {
        'steps_today': 4231,
        'heart_rate': {'bpm': 72, 'at': '2026-08-24T11:52:00.000Z'},
      },
    );
    addTearDown(heartbeatWithVitals.stop);

    presence.emit(const DevicePresence(battery: 62, charging: false));
    await heartbeatWithVitals.pingNow();

    final sent = repository.sent.single;
    expect(sent['steps_today'], 4231);
    expect(sent['heart_rate'], {'bpm': 72, 'at': '2026-08-24T11:52:00.000Z'});
    // ...alongside, not instead of, everything else.
    expect(sent['battery'], 62);
    expect(sent.containsKey('timezone'), isTrue);
  });

  test(
    'a null from extraTelemetry (opt-in off, desktop) writes no keys',
    () async {
      final heartbeatWithVitals = HeartbeatService(
        repository,
        const _FakeDeviceInfoService(),
        presenceService: presence,
        extraTelemetry: () async => null,
      );
      addTearDown(heartbeatWithVitals.stop);

      await heartbeatWithVitals.pingNow();

      expect(repository.sent.single.containsKey('steps_today'), isFalse);
      expect(repository.sent.single.containsKey('heart_rate'), isFalse);
    },
  );

  test('a track change still triggers one', () async {
    heartbeat.start();
    await pumpEventQueue();
    final beforeCount = repository.sent.length;

    presence.emit(
      const DevicePresence(
        nowPlaying: NowPlaying(
          title: 'Marigold',
          state: NowPlayingState.playing,
        ),
        battery: 62,
        charging: false,
      ),
    );
    await pumpEventQueue();

    expect(repository.sent.length, greaterThan(beforeCount));
  });
}

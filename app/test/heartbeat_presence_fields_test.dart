import 'dart:async';

import 'package:couples_app/data/repositories/device_repository.dart';
import 'package:couples_app/data/services/device_info_service.dart';
import 'package:couples_app/data/services/heartbeat_service.dart';
import 'package:couples_app/data/services/presence/presence_service.dart';
import 'package:couples_app/domain/models/now_playing.dart';
import 'package:couples_app/domain/models/partner_status.dart';
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

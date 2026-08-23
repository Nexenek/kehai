import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pocketbase/pocketbase.dart';

import 'package:couples_app/data/services/background/location_publisher.dart';

/// A [LocationSource] the test drives entirely by hand — no platform
/// channel, no real GPS. Tracks every call so tests can assert on
/// subscribe/resubscribe behaviour without a fake clock.
class _FakeLocationSource implements LocationSource {
  LocationPermission permission = LocationPermission.denied;

  int checkPermissionCalls = 0;
  int getPositionStreamCalls = 0;
  int getCurrentPositionCalls = 0;
  LocationSettings? lastStreamSettings;

  final _controller = StreamController<Position>.broadcast();

  Position nextCurrentPosition = _position();

  /// Only meaningful once something has actually listened — used to prove
  /// [LocationPublisher.stop] really tears its subscription down rather
  /// than just forgetting about it.
  bool get hasListener => _controller.hasListener;

  void emit(Position position) => _controller.add(position);

  @override
  Future<LocationPermission> checkPermission() async {
    checkPermissionCalls++;
    return permission;
  }

  @override
  Stream<Position> getPositionStream(LocationSettings settings) {
    getPositionStreamCalls++;
    lastStreamSettings = settings;
    return _controller.stream;
  }

  @override
  Future<Position> getCurrentPosition(LocationSettings settings) async {
    getCurrentPositionCalls++;
    return nextCurrentPosition;
  }
}

Position _position({
  double lat = 52.2297,
  double lon = 21.0122,
  double accuracy = 15,
  double speed = 2.5,
}) => Position(
  latitude: lat,
  longitude: lon,
  timestamp: DateTime.utc(2026, 8, 23, 12),
  accuracy: accuracy,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: speed,
  speedAccuracy: 0,
);

/// A PocketBase client that's "logged in" enough for [LocationPublisher] to
/// build an auth header from — no network involved until a request is
/// actually sent, which the test intercepts via [http.Client].
PocketBase _authedClient({String email = 'us@kehai.test', String token = 'tok123'}) {
  final pb = PocketBase('https://kehai.example');
  pb.authStore.save(
    token,
    RecordModel({
      'id': 'u1',
      'collectionId': 'c',
      'collectionName': 'users',
      'email': email,
    }),
  );
  return pb;
}

void main() {
  group('buildOwnTracksPayload', () {
    test('includes every provided field, tst in seconds', () {
      final payload = buildOwnTracksPayload(
        lat: 52.2297,
        lon: 21.0122,
        timestamp: DateTime.utc(2026, 8, 23, 12, 0, 30),
        accuracyMeters: 15,
        batteryPercent: 64,
        speedMetersPerSecond: 10,
      );

      expect(payload['_type'], 'location');
      expect(payload['lat'], 52.2297);
      expect(payload['lon'], 21.0122);
      expect(payload['acc'], 15);
      expect(payload['batt'], 64);
      // OwnTracks' `vel` is km/h; geolocator's speed is m/s.
      expect(payload['vel'], closeTo(36.0, 1e-9));
      // Unix *seconds*, not the millisecond timestamps used elsewhere in
      // this app.
      expect(payload['tst'], 1787486430);
    });

    test('omits non-positive accuracy/battery instead of sending a lie', () {
      final payload = buildOwnTracksPayload(
        lat: 1,
        lon: 2,
        timestamp: DateTime.utc(2026, 1, 1),
        accuracyMeters: 0,
        batteryPercent: -1,
      );

      expect(payload.containsKey('acc'), isFalse);
      expect(payload.containsKey('batt'), isFalse);
    });

    test('omits vel/acc/batt entirely when null', () {
      final payload = buildOwnTracksPayload(
        lat: 1,
        lon: 2,
        timestamp: DateTime.utc(2026, 1, 1),
      );

      expect(payload.keys, containsAll(['_type', 'lat', 'lon', 'tst']));
      expect(payload.containsKey('acc'), isFalse);
      expect(payload.containsKey('batt'), isFalse);
      expect(payload.containsKey('vel'), isFalse);
    });

    test('a stationary zero speed is still a real reading, not omitted', () {
      final payload = buildOwnTracksPayload(
        lat: 1,
        lon: 2,
        timestamp: DateTime.utc(2026, 1, 1),
        speedMetersPerSecond: 0,
      );

      expect(payload['vel'], 0);
    });
  });

  group('buildBasicAuthHeader', () {
    test('base64s "username:password" per RFC 7617', () {
      final header = buildBasicAuthHeader(
        username: 'us@kehai.test',
        password: 'tok123',
      );

      expect(
        header,
        'Basic ${base64Encode(utf8.encode('us@kehai.test:tok123'))}',
      );
      // Sanity-decode it back rather than trust a second encoding.
      final decoded = utf8.decode(
        base64Decode(header.substring('Basic '.length)),
      );
      expect(decoded, 'us@kehai.test:tok123');
    });
  });

  group('LocationPublisher', () {
    test('setEnabled(true) without permission never subscribes', () async {
      final source = _FakeLocationSource()
        ..permission = LocationPermission.denied;
      final publisher = LocationPublisher(
        pb: _authedClient(),
        locationSource: source,
        httpClient: MockClient((_) async => http.Response('[]', 200)),
      );

      await publisher.setEnabled(true);

      expect(source.getPositionStreamCalls, 0);
      expect(publisher.isActive, isFalse);
    });

    test(
      'setEnabled(true) with while-in-use permission subscribes with the '
      'significant-changes settings',
      () async {
        final source = _FakeLocationSource()
          ..permission = LocationPermission.whileInUse;
        final publisher = LocationPublisher(
          pb: _authedClient(),
          locationSource: source,
          httpClient: MockClient((_) async => http.Response('[]', 200)),
        );

        await publisher.setEnabled(true);

        expect(source.getPositionStreamCalls, 1);
        expect(publisher.isActive, isTrue);
        expect(source.lastStreamSettings?.distanceFilter, 250);
        expect(source.lastStreamSettings?.accuracy, LocationAccuracy.medium);
      },
    );

    test('a position fix posts the OwnTracks payload with a Basic auth header', () async {
      final source = _FakeLocationSource()
        ..permission = LocationPermission.always;
      http.Request? captured;
      final publisher = LocationPublisher(
        pb: _authedClient(email: 'us@kehai.test', token: 'tok123'),
        locationSource: source,
        httpClient: MockClient((request) async {
          captured = request;
          return http.Response('[]', 200);
        }),
        batteryLevel: () => 55,
        now: () => DateTime.utc(2026, 8, 23, 12, 0, 30),
      );

      await publisher.setEnabled(true);
      source.emit(_position());
      // Let the async listener callback run.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(captured, isNotNull);
      expect(captured!.url.toString(), 'https://kehai.example/api/owntracks');
      expect(
        captured!.headers['Authorization'],
        buildBasicAuthHeader(username: 'us@kehai.test', password: 'tok123'),
      );
      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body['_type'], 'location');
      expect(body['lat'], 52.2297);
      expect(body['lon'], 21.0122);
      expect(body['batt'], 55);
      expect(body['tst'], 1787486430);
    });

    test('stop() cancels the subscription — a later fix posts nothing', () async {
      final source = _FakeLocationSource()
        ..permission = LocationPermission.always;
      var postCount = 0;
      final publisher = LocationPublisher(
        pb: _authedClient(),
        locationSource: source,
        httpClient: MockClient((_) async {
          postCount++;
          return http.Response('[]', 200);
        }),
      );

      await publisher.setEnabled(true);
      source.emit(_position());
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(postCount, 1);

      await publisher.setEnabled(false);
      expect(publisher.isActive, isFalse);
      expect(source.hasListener, isFalse);

      // The fake's controller is still open (it's shared across the test),
      // but nothing should be listening any more.
      source.emit(_position());
      await Future<void>.delayed(Duration.zero);
      expect(postCount, 1);
    });

    test('re-applying setEnabled(true) while already active is a no-op', () async {
      final source = _FakeLocationSource()
        ..permission = LocationPermission.always;
      final publisher = LocationPublisher(
        pb: _authedClient(),
        locationSource: source,
        httpClient: MockClient((_) async => http.Response('[]', 200)),
      );

      await publisher.setEnabled(true);
      await publisher.setEnabled(true);
      await publisher.setEnabled(true);

      expect(source.getPositionStreamCalls, 1);
    });

    test(
      'a later permission grant is picked up by re-applying setEnabled(true)',
      () async {
        final source = _FakeLocationSource()
          ..permission = LocationPermission.denied;
        final publisher = LocationPublisher(
          pb: _authedClient(),
          locationSource: source,
          httpClient: MockClient((_) async => http.Response('[]', 200)),
        );

        await publisher.setEnabled(true);
        expect(publisher.isActive, isFalse);

        // The user walks through the superpowers screen's grant flow —
        // permission is now held, but nobody called setEnabled(false) in
        // between (KehaiTaskHandler/AppController just re-apply `true`).
        source.permission = LocationPermission.whileInUse;
        await publisher.setEnabled(true);

        expect(publisher.isActive, isTrue);
        expect(source.getPositionStreamCalls, 1);
      },
    );

    test('no auth token yet: a fix is silently dropped, never posted', () async {
      final source = _FakeLocationSource()
        ..permission = LocationPermission.always;
      var postCount = 0;
      final pb = PocketBase('https://kehai.example'); // never authed
      final publisher = LocationPublisher(
        pb: pb,
        locationSource: source,
        httpClient: MockClient((_) async {
          postCount++;
          return http.Response('[]', 200);
        }),
      );

      await publisher.setEnabled(true);
      source.emit(_position());
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(postCount, 0);
    });

    test('a network failure is swallowed, not rethrown', () async {
      final source = _FakeLocationSource()
        ..permission = LocationPermission.always;
      final publisher = LocationPublisher(
        pb: _authedClient(),
        locationSource: source,
        httpClient: MockClient((_) async => throw Exception('offline')),
      );

      await publisher.setEnabled(true);
      // The important assertion is simply that this never throws — a bad
      // connection must never crash the isolate the publisher runs in.
      source.emit(_position());
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(publisher.isActive, isTrue);
    });
  });
}

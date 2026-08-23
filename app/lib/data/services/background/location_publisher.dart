import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:pocketbase/pocketbase.dart';

/// Builds the OwnTracks-shaped location payload posted to `/api/owntracks`
/// (kb/contracts.md "Location": `{"_type":"location", "lat", "lon", "acc",
/// "batt", "tst", "vel", ...}`; non-location `_type`s are ignored, so we
/// only ever send this one shape).
///
/// `tst` is Unix **seconds** — OwnTracks' native unit, not the millisecond
/// timestamps the rest of this app uses. [accuracyMeters]/[batteryPercent]
/// use the same "non-positive means unknown, omit the key" convention as
/// [LocationRepository]'s read side — the contract says absent keys are
/// fine, and a fabricated 0% battery or 0m accuracy is worse than silence.
/// [speedMetersPerSecond] comes straight off [Position.speed] (m/s);
/// OwnTracks' `vel` is km/h, so it's converted here.
///
/// Pure and public so it's directly testable without a real [Position] or
/// network call.
@visibleForTesting
Map<String, dynamic> buildOwnTracksPayload({
  required double lat,
  required double lon,
  required DateTime timestamp,
  double? accuracyMeters,
  double? batteryPercent,
  double? speedMetersPerSecond,
}) {
  final payload = <String, dynamic>{
    '_type': 'location',
    'lat': lat,
    'lon': lon,
    'tst': timestamp.toUtc().millisecondsSinceEpoch ~/ 1000,
  };
  if (accuracyMeters != null && accuracyMeters > 0) {
    payload['acc'] = accuracyMeters;
  }
  if (batteryPercent != null && batteryPercent > 0) {
    payload['batt'] = batteryPercent;
  }
  if (speedMetersPerSecond != null && speedMetersPerSecond >= 0) {
    payload['vel'] = speedMetersPerSecond * 3.6;
  }
  return payload;
}

/// The `Authorization: Basic ...` header value for `/api/owntracks`
/// (kb/contracts.md: "Basic auth — username = account email, password =
/// account password OR a PB auth token"). We always send the token, never
/// the password — it's what [PocketBase]'s [AuthStore] actually has on
/// hand, and the route tries token auth first.
@visibleForTesting
String buildBasicAuthHeader({required String username, required String password}) {
  return 'Basic ${base64Encode(utf8.encode('$username:$password'))}';
}

/// Thin seam over the static `Geolocator` API so [LocationPublisher] is
/// unit-testable without a real platform channel — same shape as
/// `AndroidPresenceChannel` wrapping platform calls elsewhere.
abstract class LocationSource {
  Future<LocationPermission> checkPermission();
  Stream<Position> getPositionStream(LocationSettings settings);
  Future<Position> getCurrentPosition(LocationSettings settings);
}

class GeolocatorLocationSource implements LocationSource {
  const GeolocatorLocationSource();

  @override
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();

  @override
  Stream<Position> getPositionStream(LocationSettings settings) =>
      Geolocator.getPositionStream(locationSettings: settings);

  @override
  Future<Position> getCurrentPosition(LocationSettings settings) =>
      Geolocator.getCurrentPosition(locationSettings: settings);
}

/// Posts this device's location to the server's OwnTracks-compatible ingest
/// route, so the Kehai app itself can be someone's "tracker" and they never
/// have to install OwnTracks separately (kb/contracts.md: "The app itself
/// MAY also post its own location later via the same route with the same
/// auth").
///
/// Runs wherever presence currently lives — the background isolate
/// ([KehaiTaskHandler]) when the foreground service owns it, or the UI
/// isolate ([AppController]) when it doesn't — never both at once (same
/// single-writer rule as [HeartbeatService]/device rows). Ownership and the
/// `shareLocation` opt-in are the caller's job; this class just does what
/// [setEnabled] last told it, and only touches geolocator/network when
/// asked.
///
/// Battery pattern (kb/platform-android.md "24/7 background operation",
/// OwnTracks-derived): a significant-changes position stream
/// (`distanceFilter: 250`, medium/"balanced" accuracy — Android's
/// `PRIORITY_BALANCED_POWER_ACCURACY`) as the baseline, plus a 15-minute
/// timer fallback so a phone that hasn't moved 250m still refreshes its
/// staleness rather than looking abandoned on the map.
///
/// Every failure mode (no permission yet, location services off, network
/// down, server unreachable) is caught and logged, never rethrown — a
/// missed fix just means the next one (stream event or timer tick) tries
/// again, exactly like [HeartbeatService.pingNow].
class LocationPublisher {
  LocationPublisher({
    required PocketBase pb,
    LocationSource locationSource = const GeolocatorLocationSource(),
    http.Client? httpClient,
    double? Function() batteryLevel = _noBattery,
    DateTime Function() now = DateTime.now,
    Duration fallbackInterval = const Duration(minutes: 15),
    LocationSettings? locationSettings,
  }) : _pb = pb,
       _locationSource = locationSource,
       _httpClient = httpClient ?? http.Client(),
       _batteryLevel = batteryLevel,
       _now = now,
       _fallbackInterval = fallbackInterval,
       _locationSettings =
           locationSettings ??
           const LocationSettings(
             accuracy: LocationAccuracy.medium,
             distanceFilter: 250,
           );

  static double? _noBattery() => null;

  final PocketBase _pb;
  final LocationSource _locationSource;
  final http.Client _httpClient;
  final double? Function() _batteryLevel;
  final DateTime Function() _now;
  final Duration _fallbackInterval;
  final LocationSettings _locationSettings;

  StreamSubscription<Position>? _positionSub;
  Timer? _fallbackTimer;

  /// Whether a position stream is currently open. False both when
  /// [setEnabled] hasn't been told to run yet and when it has but
  /// permission isn't granted — either way, nothing is being reported.
  bool get isActive => _positionSub != null;

  /// Applies the `shareLocation` opt-in. Safe — and cheap — to call
  /// repeatedly with the same value: re-applying `true` while already
  /// active is a no-op, and re-applying it after a permission grant that
  /// arrived since the last call is exactly how a stalled publisher
  /// recovers (see [KehaiTaskHandler]'s per-tick re-application and
  /// `AppController.setShareLocation`).
  Future<void> setEnabled(bool enabled) async {
    if (!enabled) {
      await stop();
      return;
    }
    await _start();
  }

  Future<void> _start() async {
    if (_positionSub != null) return;

    LocationPermission permission;
    try {
      permission = await _locationSource.checkPermission();
    } catch (e) {
      debugPrint('LocationPublisher: permission check failed: $e');
      return;
    }
    // Either while-in-use or always is enough to try — the "phone
    // superpowers" screen is where the honest two-step grant flow lives;
    // this class just waits quietly until one of them is true.
    if (permission != LocationPermission.always &&
        permission != LocationPermission.whileInUse) {
      return;
    }

    try {
      _positionSub = _locationSource
          .getPositionStream(_locationSettings)
          .listen(
            (position) => unawaited(_publish(position)),
            onError: (Object e) {
              debugPrint('LocationPublisher: position stream error: $e');
            },
          );
    } catch (e) {
      debugPrint('LocationPublisher: could not start position stream: $e');
      return;
    }

    _fallbackTimer?.cancel();
    _fallbackTimer = Timer.periodic(_fallbackInterval, (_) => _fallbackFix());
  }

  /// A stationary phone never crosses `distanceFilter`, so without this the
  /// map's "as of Xh ago" would grow stale forever even though the fix
  /// itself hasn't changed. Fires independently of the stream.
  Future<void> _fallbackFix() async {
    try {
      final position = await _locationSource.getCurrentPosition(
        _locationSettings,
      );
      await _publish(position);
    } catch (e) {
      debugPrint('LocationPublisher: fallback fix failed: $e');
    }
  }

  Future<void> _publish(Position position) async {
    try {
      final username = _pb.authStore.record?.get<String>('email', '') ?? '';
      final password = _pb.authStore.token;
      if (username.isEmpty || password.isEmpty) return;

      final payload = buildOwnTracksPayload(
        lat: position.latitude,
        lon: position.longitude,
        timestamp: _now(),
        accuracyMeters: position.accuracy,
        batteryPercent: _batteryLevel(),
        speedMetersPerSecond: position.speed,
      );

      final uri = Uri.parse('${_pb.baseURL}/api/owntracks');
      await _httpClient.post(
        uri,
        headers: {
          'Authorization': buildBasicAuthHeader(
            username: username,
            password: password,
          ),
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );
    } catch (e) {
      // Server unreachable, tailnet down, whatever — dropped. The next fix
      // (stream event or fallback timer) retries naturally; a background
      // isolate must never crash over a location post.
      debugPrint('LocationPublisher: post failed: $e');
    }
  }

  Future<void> stop() async {
    await _positionSub?.cancel();
    _positionSub = null;
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
  }
}

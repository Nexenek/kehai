import 'package:pocketbase/pocketbase.dart';

import '../../domain/models/device_status.dart';
import '../../domain/models/now_playing.dart';
import '../../domain/models/partner_status.dart';

/// Heartbeats (POST /api/heartbeat) and `devices` reads — powers the
/// phone/desktop "device-source indicator" glyphs, ambient line, and
/// battery glyph on the partner card (kb/platform-desktop.md "Telemetry
/// contract (Phase 2a)").
class DeviceRepository {
  DeviceRepository(this._pb);

  final PocketBase _pb;

  DeviceStatus _fromRecord(RecordModel r) => DeviceStatus(
    id: r.id,
    ownerId: r.get<String>('owner'),
    name: r.get<String>('name'),
    kind: r.get<String>('kind'),
    lastSeen:
        DateTime.tryParse(r.get<String>('last_seen'))?.toLocal() ??
        DateTime.fromMillisecondsSinceEpoch(0),
    nowPlaying: NowPlaying.fromJson(
      r.get<Map<String, dynamic>?>('now_playing', null),
    ),
    idleSeconds: r.get<int?>('idle_seconds', null),
    // The server's NumberField stores 0 for devices that never reported
    // battery (and 0 is also its clear-on-null value), so 0 means
    // "unknown", not "0%" — a phone at a real 0% is off, not heartbeating.
    battery: _zeroAsUnreported(r.get<double?>('battery', null)),
    charging: r.get<bool?>('charging', null),
    activity: r.get<String?>('activity', null),
  );

  static double? _zeroAsUnreported(double? battery) =>
      (battery == null || battery <= 0) ? null : battery;

  /// [extra] carries any of the telemetry contract's live-state keys
  /// (`idle_seconds`, `now_playing`, `battery`, `charging`, `activity`).
  /// Per the contract, "only provided keys are written" — an absent key
  /// leaves the field untouched server-side, while an explicit `null`
  /// value clears it. Callers (see [HeartbeatService]) build this map
  /// themselves so they control which of those two a given tick means.
  Future<void> sendHeartbeat({
    required SourceKind kind,
    required String name,
    Map<String, dynamic> extra = const {},
  }) {
    return _pb.send<Map<String, dynamic>>(
      '/api/heartbeat',
      method: 'POST',
      body: {'kind': kind.name, 'name': name, ...extra},
    );
  }

  Future<List<DeviceStatus>> fetchDevicesForOwner(String ownerId) async {
    final records = await _pb
        .collection('devices')
        .getFullList(filter: 'owner = "$ownerId"');
    return records.map(_fromRecord).toList();
  }

  Future<UnsubscribeFunc> subscribe(
    void Function(DeviceStatus device) onChange,
  ) {
    return _pb.collection('devices').subscribe('*', (e) {
      if (e.record != null) onChange(_fromRecord(e.record!));
    });
  }
}

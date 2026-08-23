import 'package:pocketbase/pocketbase.dart';

import '../../domain/models/device_status.dart';
import '../../domain/models/partner_status.dart';

/// Heartbeats (POST /api/heartbeat) and `devices` reads — powers the
/// phone/desktop "device-source indicator" glyphs on the partner card.
class DeviceRepository {
  DeviceRepository(this._pb);

  final PocketBase _pb;

  DeviceStatus _fromRecord(RecordModel r) => DeviceStatus(
        id: r.id,
        ownerId: r.get<String>('owner'),
        name: r.get<String>('name'),
        kind: r.get<String>('kind'),
        lastSeen: DateTime.tryParse(r.get<String>('last_seen'))?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0),
      );

  Future<void> sendHeartbeat({required SourceKind kind, required String name}) {
    return _pb.send<Map<String, dynamic>>(
      '/api/heartbeat',
      method: 'POST',
      body: {'kind': kind.name, 'name': name},
    );
  }

  Future<List<DeviceStatus>> fetchDevicesForOwner(String ownerId) async {
    final records = await _pb.collection('devices').getFullList(filter: 'owner = "$ownerId"');
    return records.map(_fromRecord).toList();
  }

  Future<UnsubscribeFunc> subscribe(void Function(DeviceStatus device) onChange) {
    return _pb.collection('devices').subscribe('*', (e) {
      if (e.record != null) onChange(_fromRecord(e.record!));
    });
  }
}

import 'dart:async';

import '../repositories/device_repository.dart';
import 'device_info_service.dart';

/// Sends a heartbeat immediately, then every 30s while [start] is active.
/// Call [pingNow] again on app resume (spec: "every 30s while app is open +
/// on resume"). Errors are swallowed — a missed heartbeat just means the
/// device-source glyph goes dim for a bit, not worth surfacing to the user.
class HeartbeatService {
  HeartbeatService(this._deviceRepository, this._deviceInfoService);

  final DeviceRepository _deviceRepository;
  final DeviceInfoService _deviceInfoService;

  Timer? _timer;
  static const _interval = Duration(seconds: 30);

  void start() {
    pingNow();
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) => pingNow());
  }

  Future<void> pingNow() async {
    try {
      final name = await _deviceInfoService.deviceName;
      await _deviceRepository.sendHeartbeat(kind: _deviceInfoService.kind, name: name);
    } catch (_) {
      // Best-effort — next timer tick (or the next resume) will retry.
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}

import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

import '../../domain/models/partner_status.dart';

/// Figures out "what kind of device is this, and what should we call it"
/// for the heartbeat POST /api/heartbeat {kind, name} — kind is `phone` on
/// Android, `desktop` on Windows/Linux; name falls back to hostname/model.
class DeviceInfoService {
  const DeviceInfoService();

  SourceKind get kind {
    if (Platform.isAndroid) return SourceKind.phone;
    return SourceKind.desktop;
  }

  Future<String> get deviceName async {
    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await plugin.androidInfo;
        final model = info.model;
        return model.isNotEmpty ? model : 'android phone';
      }
      if (Platform.isLinux) {
        final info = await plugin.linuxInfo;
        return info.prettyName.isNotEmpty ? info.prettyName : _hostnameOrFallback('linux desktop');
      }
      if (Platform.isWindows) {
        final info = await plugin.windowsInfo;
        return info.computerName.isNotEmpty ? info.computerName : _hostnameOrFallback('windows desktop');
      }
    } catch (_) {
      // Fall through to hostname fallback below — heartbeats shouldn't
      // block on device-info plugin hiccups.
    }
    return _hostnameOrFallback('this device');
  }

  String _hostnameOrFallback(String fallback) {
    try {
      final host = Platform.localHostname;
      return host.isNotEmpty ? host : fallback;
    } catch (_) {
      return fallback;
    }
  }
}

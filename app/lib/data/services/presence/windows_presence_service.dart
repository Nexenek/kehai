import 'dart:async';

import 'package:flutter/services.dart';

import '../../../domain/models/now_playing.dart';
import 'presence_service.dart';
import 'windows_foreground_app_mapper.dart';
import 'windows_player_mapper.dart';

/// Windows implementation of [PresenceService]:
/// `GlobalSystemMediaTransportControlsSessionManager` (WinRT) for
/// now-playing, `GetLastInputInfo` for idle time — both read via the native
/// `app.kehai/presence` MethodChannel (`windows/runner/presence_channel.cpp`)
/// — see kb/platform-desktop.md's "Now-playing" / "Idle / presence" tables.
///
/// Polls every [pollInterval] rather than pushing from native, mirroring
/// [LinuxPresenceService]'s reasoning: GSMTC sessions come and go as apps
/// open/close media just like MPRIS names do, so polling keeps this to one
/// code path instead of chasing session-changed events across a platform
/// channel — at the cost of up to [pollInterval] of staleness, which is
/// fine against a 30s heartbeat cadence.
///
/// Every channel call is individually try/catched and time-boxed
/// ([_callTimeout]) — an unsupported Windows build (channel missing, no
/// current media session, GSMTC unavailable pre-Windows 10 1809) degrades
/// to [DevicePresence.empty] forever, never a crash or a hung poll.
class WindowsPresenceService implements PresenceService {
  WindowsPresenceService({
    MethodChannel? channel,
    this.pollInterval = const Duration(seconds: 5),
  }) : _channel = channel ?? const MethodChannel('app.kehai/presence');

  final MethodChannel _channel;
  final Duration pollInterval;

  final _controller = StreamController<DevicePresence>.broadcast();
  DevicePresence _current = DevicePresence.empty;
  Timer? _timer;
  bool _polling = false;

  static const _callTimeout = Duration(seconds: 3);

  @override
  DevicePresence get current => _current;

  @override
  Stream<DevicePresence> get onChange => _controller.stream;

  @override
  Future<void> start() async {
    _timer?.cancel();
    unawaited(_poll());
    _timer = Timer.periodic(pollInterval, (_) => unawaited(_poll()));
  }

  Future<void> _poll() async {
    if (_polling) return; // don't overlap polls if one runs long
    _polling = true;
    try {
      final nowPlaying = await _pollNowPlaying();
      final idleSeconds = await _pollIdleSeconds();
      final next = DevicePresence(
        nowPlaying: nowPlaying,
        idleSeconds: idleSeconds,
      );
      if (next != _current) {
        _current = next;
        if (!_controller.isClosed) _controller.add(next);
      }
    } catch (_) {
      // Never let a flaky channel call take the presence poller down —
      // degrade to "no reading this tick" and try again next tick.
    } finally {
      _polling = false;
    }
  }

  Future<NowPlaying?> _pollNowPlaying() async {
    try {
      final result = await _channel
          .invokeMethod<Object?>('getNowPlaying')
          .timeout(_callTimeout);
      return WindowsPlayerMapper.map(result);
    } catch (_) {
      // No channel (non-Windows/tests without a mock), GSMTC not present,
      // or the native call threw — no now-playing signal this tick.
      return null;
    }
  }

  Future<int?> _pollIdleSeconds() async {
    try {
      final result = await _channel
          .invokeMethod<Object?>('getIdleSeconds')
          .timeout(_callTimeout);
      if (result is int) return result;
      if (result is num) return result.toInt();
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Raw passthrough of the native `getForegroundApp` result — the
  /// currently-focused window's process name + title. Not wired into
  /// [current]/[onChange]/the heartbeat: this is deliberately just the
  /// native read, ungated by any privacy opt-in and with no
  /// friendly-name/allowlist mapping applied yet — both land in a later
  /// pass. Callers that want this today (e.g. an opt-in settings preview)
  /// call it directly.
  Future<ForegroundApp?> getForegroundApp() async {
    try {
      final result = await _channel
          .invokeMethod<Object?>('getForegroundApp')
          .timeout(_callTimeout);
      return WindowsForegroundAppMapper.map(result);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    await _controller.close();
  }
}

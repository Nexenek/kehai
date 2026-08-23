import 'dart:async';

import 'package:flutter/services.dart';

import '../../../domain/activity_mapper.dart';
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

  /// The `shareFocusedApp` per-device opt-in (kb/features.md "Focused-app
  /// status"). Off by default and off means *never even asked*: when this
  /// is false [_poll] skips the native `getForegroundApp` call entirely
  /// rather than reading it and merely discarding the result — the app
  /// genuinely doesn't look unless the user turned this on. Set by
  /// `AppController` from `PrefsService` on launch and again the instant the
  /// sharing-settings toggle changes.
  bool shareFocusedApp = false;

  /// The `shareUnknownApps` opt-in: when true, an exe with no entry in
  /// `ActivityMapper`'s table still gets a cleaned-up guess instead of
  /// staying silent. Meaningless while [shareFocusedApp] is off.
  bool shareUnknownApps = false;

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
      final activity = await _pollActivity();
      final next = DevicePresence(
        nowPlaying: nowPlaying,
        idleSeconds: idleSeconds,
        activity: activity,
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

  /// [shareFocusedApp]-gated foreground-app read, mapped through
  /// [ActivityMapper] into the `activity` value [_poll] puts on
  /// [DevicePresence]. Returns null immediately (no channel call at all)
  /// when the opt-in is off.
  Future<String?> _pollActivity() async {
    if (!shareFocusedApp) return null;
    final foreground = await getForegroundApp();
    return ActivityMapper.mapWindowsExe(
      foreground?.exe,
      shareUnknown: shareUnknownApps,
    );
  }

  /// Raw passthrough of the native `getForegroundApp` result — the
  /// currently-focused window's process name + title. Ungated by
  /// [shareFocusedApp] and with no friendly-name mapping applied — that's
  /// [_pollActivity]'s job. Exposed publicly for a settings-screen preview
  /// of "here's what we'd share" ahead of turning the toggle on.
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

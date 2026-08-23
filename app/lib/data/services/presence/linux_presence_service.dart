import 'dart:async';

import 'package:dbus/dbus.dart';

import '../../../domain/activity_mapper.dart';
import '../../../domain/models/now_playing.dart';
import 'linux_foreground_app_detector.dart';
import 'mpris_mapper.dart';
import 'presence_service.dart';

/// Linux implementation of [PresenceService]: MPRIS 2 for now-playing,
/// `org.freedesktop.ScreenSaver` then GNOME `Mutter.IdleMonitor` for idle
/// time — see kb/platform-desktop.md's "Now-playing" / "Idle / presence"
/// tables — plus [LinuxForegroundAppDetector] for the opt-in "focused-app
/// status" `activity` signal (kb/features.md), gated the same way as
/// `WindowsPresenceService.shareFocusedApp`. Polls every [pollInterval]
/// rather than chasing
/// `PropertiesChanged` signals: MPRIS players come and go on the session
/// bus constantly (a browser opening/closing an MPRIS name on every tab
/// navigation is common), so subscribing per-player would mean
/// re-subscribing on almost every poll anyway — plain polling keeps this
/// to one code path instead of two, at the cost of up to [pollInterval] of
/// staleness, which is fine against a 30s heartbeat cadence.
///
/// Every D-Bus call is individually try/catched and time-boxed
/// ([_callTimeout]) — an unsupported desktop (no MPRIS players, no
/// ScreenSaver/Mutter idle interface — the expected case running under
/// WSLg) degrades to [DevicePresence.empty] forever, never a crash or a
/// hung poll.
class LinuxPresenceService implements PresenceService {
  LinuxPresenceService({
    DBusClient? sessionBus,
    LinuxForegroundAppDetector? foregroundAppDetector,
    this.pollInterval = const Duration(seconds: 5),
  }) : _ownsBus = sessionBus == null,
       _bus = sessionBus ?? DBusClient.session(),
       _foregroundAppDetector =
           foregroundAppDetector ?? LinuxForegroundAppDetector();

  final DBusClient _bus;
  final bool _ownsBus;
  final Duration pollInterval;
  final LinuxForegroundAppDetector _foregroundAppDetector;

  final _controller = StreamController<DevicePresence>.broadcast();
  DevicePresence _current = DevicePresence.empty;
  Timer? _timer;
  bool _polling = false;

  /// The `shareFocusedApp` per-device opt-in (kb/features.md "Focused-app
  /// status") — same contract as `WindowsPresenceService.shareFocusedApp`:
  /// off means [_pollActivity] skips [_foregroundAppDetector] entirely
  /// rather than reading it and discarding the result. Set by
  /// `AppController` from `PrefsService` on launch and again the instant
  /// the sharing-settings toggle changes.
  bool shareFocusedApp = false;

  /// The `shareUnknownApps` opt-in — see `WindowsPresenceService`'s field
  /// of the same name. Meaningless while [shareFocusedApp] is off.
  bool shareUnknownApps = false;

  static const _callTimeout = Duration(seconds: 2);

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
      // Never let a flaky bus call take the presence poller down —
      // degrade to "no reading this tick" and try again next tick.
    } finally {
      _polling = false;
    }
  }

  Future<NowPlaying?> _pollNowPlaying() async {
    List<String> names;
    try {
      names = await _bus.listNames().timeout(_callTimeout);
    } catch (_) {
      return null; // no session bus, or it doesn't answer ListNames — bail
    }
    final playerNames =
        names.where((n) => n.startsWith('org.mpris.MediaPlayer2.')).toList()
          ..sort();

    NowPlaying? bestPaused;
    for (final name in playerNames) {
      final snapshot = await _readPlayer(name);
      if (snapshot == null) continue;
      if (snapshot.state == NowPlayingState.playing)
        return snapshot; // Playing beats Paused
      bestPaused ??= snapshot;
    }
    return bestPaused;
  }

  Future<NowPlaying?> _readPlayer(String busName) async {
    try {
      final obj = DBusRemoteObject(
        _bus,
        name: busName,
        path: DBusObjectPath('/org/mpris/MediaPlayer2'),
      );
      final props = await obj
          .getAllProperties('org.mpris.MediaPlayer2.Player')
          .timeout(_callTimeout);
      final statusValue = props['PlaybackStatus'];
      final status = statusValue is DBusString ? statusValue.value : null;
      final metadataValue = props['Metadata'];
      final metadata = metadataValue is DBusDict
          ? metadataValue.asStringVariantDict()
          : const <String, DBusValue>{};
      return MprisMapper.map(
        busName: busName,
        playbackStatus: status,
        metadata: metadata,
      );
    } catch (_) {
      // Player vanished mid-poll, doesn't fully implement the interface,
      // or is just slow to answer — skip it, not fatal to the poll.
      return null;
    }
  }

  /// [shareFocusedApp]-gated focused-window read, mapped through
  /// [ActivityMapper] into the `activity` value [_poll] puts on
  /// [DevicePresence]. Returns null immediately (no detection attempted at
  /// all) when the opt-in is off — mirrors
  /// `WindowsPresenceService._pollActivity`.
  Future<String?> _pollActivity() async {
    if (!shareFocusedApp) return null;
    LinuxForegroundWindow? window;
    try {
      window = await _foregroundAppDetector.detect().timeout(_callTimeout);
    } catch (_) {
      return null;
    }
    final label = ActivityMapper.mapLinuxClass(
      window?.wmClass,
      shareUnknown: shareUnknownApps,
    );
    return ActivityMapper.refineBrowserLabel(label, window?.title);
  }

  Future<int?> _pollIdleSeconds() async {
    final screenSaverIdle = await _tryScreenSaverIdle();
    if (screenSaverIdle != null) return screenSaverIdle;
    return _tryMutterIdle();
  }

  /// `org.freedesktop.ScreenSaver.GetSessionIdleTime` — a de-facto
  /// extension some screensaver daemons (KDE's among them) implement on
  /// top of the freedesktop ScreenSaver interface; returns milliseconds.
  /// Most desktops (and WSLg, which has no screensaver daemon at all)
  /// don't implement this — that's expected, not an error worth logging.
  Future<int?> _tryScreenSaverIdle() async {
    try {
      final obj = DBusRemoteObject(
        _bus,
        name: 'org.freedesktop.ScreenSaver',
        path: DBusObjectPath('/org/freedesktop/ScreenSaver'),
      );
      final result = await obj
          .callMethod('org.freedesktop.ScreenSaver', 'GetSessionIdleTime', [])
          .timeout(_callTimeout);
      final ms = result.returnValues.isEmpty
          ? null
          : _asInt(result.returnValues.first);
      return ms == null ? null : ms ~/ 1000;
    } catch (_) {
      return null;
    }
  }

  /// GNOME Mutter's private `IdleMonitor.GetIdletime` — returns
  /// milliseconds since last input, GNOME's only exposed idle signal
  /// (Mutter never implements the generic ScreenSaver extension above).
  Future<int?> _tryMutterIdle() async {
    try {
      final obj = DBusRemoteObject(
        _bus,
        name: 'org.gnome.Mutter.IdleMonitor',
        path: DBusObjectPath('/org/gnome/Mutter/IdleMonitor/Core'),
      );
      final result = await obj
          .callMethod('org.gnome.Mutter.IdleMonitor', 'GetIdletime', [])
          .timeout(_callTimeout);
      final ms = result.returnValues.isEmpty
          ? null
          : _asInt(result.returnValues.first);
      return ms == null ? null : ms ~/ 1000;
    } catch (_) {
      return null;
    }
  }

  static int? _asInt(DBusValue value) {
    final native = value.toNative();
    return native is int ? native : null;
  }

  @override
  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    await _controller.close();
    if (_ownsBus) {
      try {
        await _bus.close();
      } catch (_) {
        // Best-effort cleanup — nothing useful to do if this fails.
      }
    }
  }
}

import 'package:flutter/foundation.dart';

import '../../../../domain/models/now_playing.dart';
import '../presence_service.dart';

/// Pure Android-snapshot -> [DevicePresence] mapping, deliberately kept
/// away from the platform channels in `AndroidPresenceService` (and away
/// from Kotlin) so all of it is unit-testable with plain maps. The Kotlin
/// side stays "read the OS, hand Dart the raw values"; every judgement
/// call — which media session wins, what counts as idle, what a player is
/// called — lives here.
///
/// Signal sources behind these fields (kb/platform-android.md "Presence /
/// status signals"):
/// - `battery` / `charging`: `ACTION_BATTERY_CHANGED` sticky broadcast.
/// - `screen_on` / `screen_off_since_millis`: `ACTION_SCREEN_ON`/`_OFF` +
///   `ACTION_USER_PRESENT`.
/// - `sessions`: `MediaSessionManager.getActiveSessions`, which needs an
///   enabled `NotificationListenerService`.
class AndroidPresenceSnapshot {
  const AndroidPresenceSnapshot({
    this.battery,
    this.charging,
    this.screenOn = true,
    this.screenOffSinceMillis,
    this.mediaListenerEnabled = false,
    this.sessions = const [],
    this.foregroundPackage,
  });

  static const empty = AndroidPresenceSnapshot();

  /// 0–100, null when the platform hasn't reported a battery reading yet.
  final double? battery;

  /// Plugged in (AC/USB/wireless), null before the first reading.
  final bool? charging;

  /// Whether the display is currently interactive.
  final bool screenOn;

  /// Wall-clock ms (epoch) of the moment the screen went off — the anchor
  /// the "idle_seconds analog" is measured from. Null while the screen is
  /// on, or if the service started with the screen already off and has no
  /// idea how long it's been that way.
  final int? screenOffSinceMillis;

  /// Whether our `NotificationListenerService` is enabled — the gate on
  /// [sessions] being populated at all. Surfaced so the "phone
  /// superpowers" screen can show live status instead of guessing.
  final bool mediaListenerEnabled;

  /// Every active media session the listener can see, freshest-first is
  /// not guaranteed — [pickSession] does the choosing.
  final List<MediaSessionSnapshot> sessions;

  /// The most-recently-foregrounded app's package id, from
  /// `PresenceMonitor.queryForegroundPackage`'s `UsageStatsManager` read
  /// over the trailing ~60s window (kb/platform-android.md's "Foreground
  /// app" row). Already gated on the Usage Access grant *and* our own
  /// `setForegroundAppEnabled` toggle on the native side — a package here
  /// means both are true. Turning either off degrades this to null, never
  /// an error. Mapping to a friendly `activity` label
  /// (`ActivityMapper.mapAndroidPackage`) happens in
  /// `AndroidPresenceService.current`, not here, since that also needs the
  /// `shareUnknownApps` opt-in this snapshot has no reason to know about.
  final String? foregroundPackage;

  /// Tolerant parse of the map the platform channel sends. Anything
  /// missing or of an unexpected type degrades to "no signal" rather than
  /// throwing — a presence source that goes quiet must never take the
  /// heartbeat down with it.
  static AndroidPresenceSnapshot fromChannel(Object? raw) {
    if (raw is! Map) return empty;
    final map = raw.map((k, v) => MapEntry(k.toString(), v));

    final rawSessions = map['sessions'];
    final sessions = <MediaSessionSnapshot>[];
    if (rawSessions is List) {
      for (final entry in rawSessions) {
        final session = MediaSessionSnapshot.fromChannel(entry);
        if (session != null) sessions.add(session);
      }
    }

    return AndroidPresenceSnapshot(
      battery: _asDouble(map['battery']),
      charging: map['charging'] is bool ? map['charging'] as bool : null,
      screenOn: map['screen_on'] is bool ? map['screen_on'] as bool : true,
      screenOffSinceMillis: _asInt(map['screen_off_since_millis']),
      mediaListenerEnabled: map['media_listener_enabled'] == true,
      sessions: sessions,
      foregroundPackage: _asNonEmptyString(map['foreground_package']),
    );
  }

  /// The screen-off-duration stand-in for desktop's "seconds since last
  /// input". Screen on means the phone is in someone's hands right now, so
  /// idle is 0; screen off measures from [screenOffSinceMillis]. A screen
  /// that's off with no known start time reports null ("no idle signal")
  /// rather than a made-up 0 — better an absent key than a wrong one.
  int? idleSeconds({required DateTime now}) {
    if (screenOn) return 0;
    final since = screenOffSinceMillis;
    if (since == null) return null;
    final elapsed = now.millisecondsSinceEpoch - since;
    return elapsed <= 0 ? 0 : elapsed ~/ 1000;
  }

  /// The one session worth reporting: a Playing one beats a Paused one,
  /// and among equals the first the platform listed wins (Android orders
  /// active sessions by priority, most-recently-active first). Sessions
  /// with no usable title or a state we don't map (stopped, buffering into
  /// nothing, error) are skipped entirely.
  NowPlaying? nowPlaying() {
    NowPlaying? bestPaused;
    for (final session in sessions) {
      final mapped = session.toNowPlaying();
      if (mapped == null) continue;
      if (mapped.state == NowPlayingState.playing) return mapped;
      bestPaused ??= mapped;
    }
    return bestPaused;
  }

  /// The full presence reading this snapshot implies, at [now]. [activity]
  /// is threaded in by the caller ([AndroidPresenceService.current]) rather
  /// than computed here, since turning [foregroundPackage] into a label
  /// needs the `shareFocusedApp`/`shareUnknownApps` opt-ins this pure,
  /// channel-driven class deliberately has no knowledge of.
  DevicePresence toPresence({required DateTime now, String? activity}) =>
      DevicePresence(
        nowPlaying: nowPlaying(),
        idleSeconds: idleSeconds(now: now),
        battery: battery,
        charging: charging,
        activity: activity,
      );

  static double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return null;
  }

  static int? _asInt(Object? value) {
    if (value is num) return value.toInt();
    return null;
  }

  static String? _asNonEmptyString(Object? value) =>
      value is String && value.isNotEmpty ? value : null;
}

/// One `MediaController`'s worth of metadata, straight off the channel.
@immutable
class MediaSessionSnapshot {
  const MediaSessionSnapshot({
    required this.packageName,
    this.appLabel,
    this.title,
    this.artist,
    this.album,
    required this.state,
  });

  /// e.g. `com.spotify.music`.
  final String packageName;

  /// The launcher label Android has for that package ("Spotify"), when
  /// `PackageManager` could resolve it.
  final String? appLabel;

  final String? title;
  final String? artist;
  final String? album;

  /// Raw `PlaybackState.getState()` int — mapped by [playbackState].
  final int state;

  static MediaSessionSnapshot? fromChannel(Object? raw) {
    if (raw is! Map) return null;
    final map = raw.map((k, v) => MapEntry(k.toString(), v));
    final package = map['package'];
    if (package is! String || package.isEmpty) return null;
    return MediaSessionSnapshot(
      packageName: package,
      appLabel: _string(map['label']),
      title: _string(map['title']),
      artist: _string(map['artist']),
      album: _string(map['album']),
      state: map['state'] is num ? (map['state'] as num).toInt() : 0,
    );
  }

  /// `PlaybackState` constants. Only playing/paused exist in the telemetry
  /// contract's `now_playing.state`, so everything else (STATE_NONE,
  /// STOPPED, ERROR, the skipping states) becomes null = nothing playing.
  /// STATE_BUFFERING counts as playing: from across the room, a track
  /// that's spinning up is playing.
  NowPlayingState? get playbackState => switch (state) {
    3 || 6 => NowPlayingState.playing, // STATE_PLAYING, STATE_BUFFERING
    2 => NowPlayingState.paused, // STATE_PAUSED
    _ => null,
  };

  /// The `now_playing.player` value: Android's own app label if we got
  /// one, else a hand-kept name for the players our couple actually uses,
  /// else a readable guess from the package id. Never the raw package
  /// name — "com.zhiliaoapp.musically" on a partner card is nobody's idea
  /// of cozy.
  String get playerLabel {
    final label = appLabel;
    if (label != null && label.trim().isNotEmpty) return label.trim();
    return prettyPackageName(packageName);
  }

  NowPlaying? toNowPlaying() {
    final mappedState = playbackState;
    if (mappedState == null) return null;
    final trackTitle = title?.trim();
    if (trackTitle == null || trackTitle.isEmpty) return null;
    return NowPlaying(
      title: trackTitle,
      artist: _blankToNull(artist),
      album: _blankToNull(album),
      player: playerLabel,
      state: mappedState,
    );
  }

  /// Fallback pretty-namer for when `PackageManager` gave us nothing
  /// (rare, but a package can be uninstalled between the session listing
  /// and the label lookup).
  static String prettyPackageName(String package) {
    const known = {
      'com.spotify.music': 'Spotify',
      'com.google.android.youtube': 'YouTube',
      'com.google.android.apps.youtube.music': 'YouTube Music',
      'com.zhiliaoapp.musically': 'TikTok',
      'com.ss.android.ugc.trill': 'TikTok',
      'deezer.android.app': 'Deezer',
      'com.soundcloud.android': 'SoundCloud',
      'tv.twitch.android.app': 'Twitch',
      'com.netflix.mediaclient': 'Netflix',
      'org.videolan.vlc': 'VLC',
      'com.plexapp.android': 'Plex',
      'org.jellyfin.mobile': 'Jellyfin',
      'com.bambuna.podcastaddict': 'Podcast Addict',
      'au.com.shiftyjelly.pocketcasts': 'Pocket Casts',
    };
    final hit = known[package];
    if (hit != null) return hit;

    // Last resort: last meaningful path segment, title-cased.
    final parts = package.split('.').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return package;
    final last = parts.last;
    if (last.isEmpty) return package;
    return last[0].toUpperCase() + last.substring(1);
  }

  static String? _string(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  @override
  bool operator ==(Object other) =>
      other is MediaSessionSnapshot &&
      other.packageName == packageName &&
      other.appLabel == appLabel &&
      other.title == title &&
      other.artist == artist &&
      other.album == album &&
      other.state == state;

  @override
  int get hashCode =>
      Object.hash(packageName, appLabel, title, artist, album, state);
}

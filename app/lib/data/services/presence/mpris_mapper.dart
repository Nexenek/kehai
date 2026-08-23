import 'package:dbus/dbus.dart';

import '../../../domain/models/now_playing.dart';

/// Pure MPRIS-metadata -> [NowPlaying] mapping, kept separate from the
/// D-Bus I/O in `LinuxPresenceService` so it can be unit-tested by handing
/// it hand-built [DBusValue]s instead of a live session bus.
class MprisMapper {
  const MprisMapper._();

  /// Maps one player's `PlaybackStatus` + `Metadata` (as returned by
  /// `org.freedesktop.DBus.Properties.GetAll` on
  /// `org.mpris.MediaPlayer2.Player`, with the outer `a{sv}` already
  /// unwrapped via [DBusDict.asStringVariantDict]) to a [NowPlaying].
  /// Returns null for `Stopped`/unknown status or metadata with no usable
  /// title — MPRIS mandates neither, and real players (Spotify's Linux
  /// client is "slightly incomplete" per kb/platform-desktop.md) sometimes
  /// send an empty dict between tracks.
  static NowPlaying? map({
    required String busName,
    required String? playbackStatus,
    required Map<String, DBusValue> metadata,
  }) {
    final state = switch (playbackStatus) {
      'Playing' => NowPlayingState.playing,
      'Paused' => NowPlayingState.paused,
      _ => null,
    };
    if (state == null) return null;

    final title = _string(metadata['xesam:title']);
    if (title == null || title.isEmpty) return null;

    return NowPlaying(
      title: title,
      artist: _firstArtist(metadata['xesam:artist']),
      album: _string(metadata['xesam:album']),
      player: playerLabel(busName),
      state: state,
    );
  }

  static String? _string(DBusValue? value) {
    if (value is DBusString) return value.value;
    return null;
  }

  static String? _firstArtist(DBusValue? value) {
    if (value is! DBusArray) return null;
    for (final child in value.children) {
      final s = _string(child);
      if (s != null && s.isNotEmpty) return s;
    }
    return null;
  }

  /// `org.mpris.MediaPlayer2.spotify` -> `spotify`; strips the
  /// `.instanceNNNN` suffix some multi-window players (Chromium tabs)
  /// append to their bus name.
  static String playerLabel(String busName) {
    const prefix = 'org.mpris.MediaPlayer2.';
    var label = busName.startsWith(prefix) ? busName.substring(prefix.length) : busName;
    final instanceIndex = label.indexOf('.instance');
    if (instanceIndex != -1) label = label.substring(0, instanceIndex);
    return label;
  }
}

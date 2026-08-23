import '../../../domain/models/now_playing.dart';

/// Pure mapping from the raw `getNowPlaying` MethodChannel result — a
/// `{title, artist, album, player, state}` map built by
/// `windows/runner/presence_channel.cpp` from GSMTC's raw session fields —
/// to [NowPlaying]. Kept separate from the channel I/O in
/// `WindowsPresenceService` so it can be unit-tested with hand-built maps
/// instead of a live platform channel, mirroring `MprisMapper` on Linux.
class WindowsPlayerMapper {
  const WindowsPlayerMapper._();

  /// Maps one `getNowPlaying` result (`null`, or the map described above —
  /// values arrive as `Object?` since `MethodChannel` decodes a
  /// `StandardMethodCodec` map as `Map<Object?, Object?>`). Returns null for
  /// anything that isn't a well-formed map with a non-empty title and a
  /// recognized state — mirrors `MprisMapper.map`'s "no usable now-playing"
  /// handling, and matches [NowPlaying.fromJson]'s own permissiveness.
  static NowPlaying? map(Object? raw) {
    if (raw is! Map) return null;
    final title = raw['title'] as String?;
    if (title == null || title.isEmpty) return null;
    final state = NowPlayingState.fromWireValue(raw['state'] as String?);
    if (state == null) return null;
    return NowPlaying(
      title: title,
      artist: _nonEmpty(raw['artist']),
      album: _nonEmpty(raw['album']),
      player: prettifyPlayerId(raw['player'] as String?),
      state: state,
    );
  }

  static String? _nonEmpty(Object? value) {
    final s = value is String ? value : null;
    return (s == null || s.isEmpty) ? null : s;
  }

  /// Prettifies a raw `SourceAppUserModelId` (AUMID, or a plain exe path
  /// for unpackaged apps) into a short label for the partner card, e.g.
  /// `Spotify.exe` -> `spotify`, a Chrome/Edge/Firefox AUMID -> `browser`.
  /// Falls back to a lowercased, path/extension-stripped version of the raw
  /// id for anything unrecognized; null input stays null (GSMTC doesn't
  /// always report `SourceAppUserModelId`).
  static String? prettifyPlayerId(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final lower = raw.toLowerCase();
    if (lower.contains('spotify')) return 'spotify';
    if (lower.contains('chrome') ||
        lower.contains('msedge') ||
        lower.contains('microsoftedge') ||
        lower.contains('firefox')) {
      return 'browser';
    }
    if (lower.contains('applemusic')) return 'apple music';
    if (lower.contains('zunemusic') || lower.contains('groove')) {
      return 'groove music';
    }
    if (lower.contains('media.player') || lower.contains('mediaplayer')) {
      return 'media player';
    }
    return _fallbackLabel(raw);
  }

  /// Best-effort cleanup for an unrecognized id: take the last path
  /// segment, drop a package-style `!AppId` suffix and a `.exe` extension,
  /// lowercase what's left.
  static String _fallbackLabel(String raw) {
    var label = raw;
    final lastSlash = label.lastIndexOf(RegExp(r'[\\/]'));
    if (lastSlash != -1) label = label.substring(lastSlash + 1);
    final bang = label.indexOf('!');
    if (bang != -1) label = label.substring(0, bang);
    if (label.toLowerCase().endsWith('.exe')) {
      label = label.substring(0, label.length - 4);
    }
    return label.toLowerCase();
  }
}

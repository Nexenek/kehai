import 'package:flutter/foundation.dart';

/// Playback state of a [NowPlaying] track — mirrors the `now_playing.state`
/// enum from the telemetry contract (kb/platform-desktop.md, "Telemetry
/// contract (Phase 2a)"): `playing` or `paused`. Anything else (stopped, no
/// player at all) is represented as a null [NowPlaying], never a third
/// state value.
enum NowPlayingState {
  playing,
  paused;

  String get wireValue => name;

  static NowPlayingState? fromWireValue(String? value) {
    return switch (value) {
      'playing' => NowPlayingState.playing,
      'paused' => NowPlayingState.paused,
      _ => null,
    };
  }
}

/// What's currently in someone's media player — the `now_playing` json
/// object on a `devices` record: `{title, artist, album, player, state}`
/// (kb/platform-desktop.md "Telemetry contract (Phase 2a)").
///
/// Equality (and therefore "did the track change") is deliberately based on
/// [title] + [artist] + [state] only — [album]/[player] still ride along in
/// the wire payload, but a metadata-only refresh of those (some players
/// resend Metadata with a fresher [album] on every poll) isn't a "track
/// changed" event worth an extra heartbeat.
@immutable
class NowPlaying {
  const NowPlaying({
    required this.title,
    this.artist,
    this.album,
    this.player,
    required this.state,
  });

  final String title;
  final String? artist;
  final String? album;
  final String? player;
  final NowPlayingState state;

  /// The partner-card ambient line, per the contract's precedence:
  /// "now_playing ♪ title — artist" (or just "♪ title" with no artist).
  String get marqueeText {
    final a = artist;
    return (a == null || a.isEmpty) ? '♪ $title' : '♪ $title — $a';
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'artist': artist,
    'album': album,
    'player': player,
    'state': state.wireValue,
  };

  /// Parses a `devices.now_playing` json value. Null/empty per the
  /// contract means "nothing playing"; a title-less or state-less payload
  /// is treated the same way rather than surfacing a broken row.
  static NowPlaying? fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return null;
    final title = json['title'] as String?;
    if (title == null || title.isEmpty) return null;
    final state = NowPlayingState.fromWireValue(json['state'] as String?);
    if (state == null) return null;
    return NowPlaying(
      title: title,
      artist: json['artist'] as String?,
      album: json['album'] as String?,
      player: json['player'] as String?,
      state: state,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NowPlaying &&
      other.title == title &&
      other.artist == artist &&
      other.state == state;

  @override
  int get hashCode => Object.hash(title, artist, state);

  @override
  String toString() => 'NowPlaying($marqueeText, ${state.wireValue})';
}

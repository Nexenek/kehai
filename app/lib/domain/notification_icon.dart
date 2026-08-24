import 'models/ambient_line.dart';

/// Every drawable name [notificationIconFor] can return, and the *only*
/// names it can ever return (enforced by the assert below). This has to
/// stay in lockstep with two other places by hand:
///
/// - the ten `<meta-data android:resource="@drawable/...">` entries in
///   AndroidManifest.xml — flutter_foreground_task's
///   `NotificationIcon.metaDataName` looks up a manifest meta-data int, not
///   an arbitrary runtime resource-name string (see
///   `KehaiForegroundTask.render`'s doc comment), so every name here needs
///   a matching manifest entry or the lookup silently resolves to icon id
///   `0` and Android falls back to a blank/default icon rather than
///   crashing (verified by reading `ForegroundService.getIconResId`:
///   `metaData.getInt(...)` on a missing key returns 0, and
///   `Notification.Builder.setSmallIcon(0)` is a documented no-op-ish
///   "use the app icon" fallback, not an exception);
/// - `tool/generate_notification_icons.py`'s `ICONS` map, which draws the
///   PNGs these names point at.
const notificationIconNames = <String>{
  'ic_stat_heart',
  'ic_stat_music',
  'ic_stat_code',
  'ic_stat_scroll',
  'ic_stat_watch',
  'ic_stat_game',
  'ic_stat_chat',
  'ic_stat_photo',
  'ic_stat_sleep',
  'ic_stat_away',
};

/// The default/fallback glyph: a plain heart. Used whenever there's no
/// ambient line, the line is presence-only ("at their computer"/"on their
/// phone" — already said by the notification text, and reads fine as a
/// heart in the status bar), or an activity line doesn't match any known
/// keyword below.
const _defaultIcon = 'ic_stat_heart';

/// (needle, icon) pairs matched against the lowercased activity text, first
/// match wins. A plain data table on purpose — same shape as the
/// needle/label tables in `activity_mapper.dart` — so a new activity label
/// just needs one more row here, no branching logic.
const _activityIconTable = <(String, String)>[
  ('coding', 'ic_stat_code'),
  ('terminal', 'ic_stat_code'),
  ('scrolling', 'ic_stat_scroll'),
  ('watching', 'ic_stat_watch'),
  ('netflix', 'ic_stat_watch'),
  ('youtube', 'ic_stat_watch'),
  ('twitch', 'ic_stat_watch'),
  ('gaming', 'ic_stat_game'),
  ('playing', 'ic_stat_game'),
  ('chatting', 'ic_stat_chat'),
  ('texting', 'ic_stat_chat'),
  ('on a call', 'ic_stat_chat'),
  ('checking email', 'ic_stat_chat'),
  ('taking photos', 'ic_stat_photo'),
  ('listening', 'ic_stat_music'),
];

/// Picks the ongoing notification's status-bar (small) icon from the
/// partner's current [AmbientLine] — the same precedence value
/// `buildPartnerNotification`'s `resolveAmbientLine` call already produces,
/// so this never re-derives presence itself.
///
/// Rules (kb/roadmap.md Wave 6 — "activity-aware status-bar icons"):
/// - `null` (nothing recent / partner unknown) -> heart.
/// - [AmbientLineKind.nowPlaying] -> music note, regardless of what's
///   playing — the marquee text already names the track.
/// - [AmbientLineKind.asleep] -> zzZ.
/// - [AmbientLineKind.away] -> the hollow/ghost heart.
/// - [AmbientLineKind.atComputer]/[AmbientLineKind.onPhone] -> heart; the
///   notification text already says "at their computer"/"on their phone",
///   a bespoke glyph for "present, doing nothing in particular" wouldn't
///   earn its keep.
/// - [AmbientLineKind.activity] -> keyword match on the (lowercased)
///   activity text via [_activityIconTable], first match wins, falling
///   back to the heart for anything unmapped (e.g. "navigating",
///   "browsing ☁", "in a meeting" — no dedicated glyph for those yet).
///
/// Pure and total: every branch returns one of [notificationIconNames],
/// which the trailing assert enforces, so a caller can hand the result
/// straight to `NotificationIcon(metaDataName: ...)` without a manual
/// allow-list check of its own.
String notificationIconFor(AmbientLine? line) {
  final icon = _resolve(line);
  assert(
    notificationIconNames.contains(icon),
    'notificationIconFor produced unknown icon "$icon"',
  );
  return icon;
}

String _resolve(AmbientLine? line) {
  if (line == null) return _defaultIcon;
  switch (line.kind) {
    case AmbientLineKind.nowPlaying:
      return 'ic_stat_music';
    case AmbientLineKind.asleep:
      return 'ic_stat_sleep';
    case AmbientLineKind.away:
      return 'ic_stat_away';
    case AmbientLineKind.atComputer:
    case AmbientLineKind.onPhone:
      return _defaultIcon;
    case AmbientLineKind.activity:
      final text = line.text.toLowerCase();
      for (final (needle, icon) in _activityIconTable) {
        if (text.contains(needle)) return icon;
      }
      return _defaultIcon;
  }
}

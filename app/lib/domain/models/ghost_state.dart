import 'package:flutter/foundation.dart';

/// Ghost mode — the *honest* location pause from kb/decisions.md ADR-6 and
/// kb/contracts.md: while it's on the server drops incoming points, and the
/// partner is told the location is paused rather than being left to wonder
/// why it went stale. There is deliberately no silent option.
///
/// The whole state lives in one nullable `users.ghost_until` date, so these
/// are pure functions over that field — no clock hidden inside, every one
/// takes `now` for testability.
enum GhostKind {
  /// Sharing normally.
  off,

  /// Paused, and it un-pauses by itself at [GhostState.until].
  until,

  /// Paused until the user turns it back on (stored as a year-2100 date).
  indefinite,
}

@immutable
class GhostState {
  const GhostState._(this.kind, this.until);

  static const off = GhostState._(GhostKind.off, null);

  const GhostState.until(DateTime this.until) : kind = GhostKind.until;

  const GhostState.indefinite(DateTime this.until)
    : kind = GhostKind.indefinite;

  final GhostKind kind;

  /// When the pause lifts. Null only for [GhostKind.off]; for
  /// [GhostKind.indefinite] it's the far-future sentinel, kept around so
  /// callers can round-trip the field without special-casing it.
  final DateTime? until;

  bool get isActive => kind != GhostKind.off;

  @override
  bool operator ==(Object other) =>
      other is GhostState && other.kind == kind && other.until == until;

  @override
  int get hashCode => Object.hash(kind, until);

  @override
  String toString() => 'GhostState($kind, until: $until)';
}

/// The "until I turn it back on" sentinel. Any `ghost_until` at or past
/// [indefiniteGhostYear] reads back as [GhostKind.indefinite] rather than
/// as "paused until 1 January 2100", which would be a silly thing to show
/// someone.
const int indefiniteGhostYear = 2100;

/// What [GhostOption.indefinite] writes to `users.ghost_until`.
final DateTime indefiniteGhostUntil = DateTime.utc(indefiniteGhostYear, 1, 1);

/// Reads the raw `ghost_until` field. Empty/missing (PocketBase returns
/// `""` for an unset date, and the field may not exist at all while the
/// server-side migration is still landing) means "not paused".
DateTime? parseGhostUntil(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  return DateTime.tryParse(raw)?.toLocal();
}

/// off / until / indefinite, from the stored field. A `ghost_until` in the
/// past is simply over — the server stops dropping points at that instant
/// without anybody having to clear the field.
GhostState resolveGhostState(DateTime? ghostUntil, {DateTime? now}) {
  if (ghostUntil == null) return GhostState.off;
  final at = now ?? DateTime.now();
  if (!ghostUntil.isAfter(at)) return GhostState.off;
  if (ghostUntil.toUtc().year >= indefiniteGhostYear) {
    return GhostState.indefinite(ghostUntil);
  }
  return GhostState.until(ghostUntil);
}

/// The three quick pauses offered in the UI (ADR-6: "one-tap ghost mode
/// (1 h / today / until-I-turn-it-on)"). `null` anywhere one of these is
/// accepted means "sharing on".
enum GhostOption { hour, untilTomorrow, indefinite }

/// The `ghost_until` value a given quick option should write — `null` for
/// "sharing on", which clears the field.
///
/// [GhostOption.untilTomorrow] is literally *tomorrow* at 08:00 local, to
/// match what its button says. Picking it at 23:00 gives nine hours; at
/// 06:00 it gives a whole day and a bit. That's the honest reading of the
/// label, and the state row always spells out the exact time it lifts.
DateTime? ghostUntilFor(GhostOption? option, {DateTime? now}) {
  final at = now ?? DateTime.now();
  return switch (option) {
    null => null,
    GhostOption.hour => at.add(const Duration(hours: 1)),
    // Dart normalizes an out-of-range day, so this is month/year safe.
    GhostOption.untilTomorrow => DateTime(at.year, at.month, at.day + 1, 8),
    GhostOption.indefinite => indefiniteGhostUntil,
  };
}

const _monthNames = <String>[
  'jan',
  'feb',
  'mar',
  'apr',
  'may',
  'jun',
  'jul',
  'aug',
  'sep',
  'oct',
  'nov',
  'dec',
];

/// A short, human "when does this lift" phrase: "20:15" today, "tomorrow
/// 8:00", "26 aug, 8:00" further out. Local time, 24h — kept
/// dependency-free rather than pulling `intl` in for one string (same call
/// as [timeAgo]).
String formatGhostUntil(DateTime until, {DateTime? now}) {
  final at = now ?? DateTime.now();
  final local = until.toLocal();
  final clock = '${local.hour}:${local.minute.toString().padLeft(2, '0')}';

  final today = DateTime(at.year, at.month, at.day);
  final day = DateTime(local.year, local.month, local.day);
  final daysAway = day.difference(today).inDays;

  if (daysAway <= 0) return clock;
  if (daysAway == 1) return 'tomorrow $clock';
  return '${local.day} ${_monthNames[local.month - 1]}, $clock';
}

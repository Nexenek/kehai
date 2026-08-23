import 'dart:ui' show Offset;

/// Pure logic behind the thumb-kiss touch area (kb/features.md
/// "Thumb-kiss") — throttling, freshness, and the "met" geometry test. No
/// Flutter widgets, no PocketBase: everything here is plain-value unit
/// testable, and [ThumbKissViewModel] (in `thumb_kiss_view_model.dart`) is
/// the only caller.

/// Minimum spacing between touch sends while a thumb is held down. ~4/s per
/// the feature brief ("throttled ~4/s") — enough to feel continuous without
/// spamming the realtime channel (kb/features.md: "cheap to build on our
/// realtime channel", not "free").
const touchSendInterval = Duration(milliseconds: 250);

/// How long a touch point (mine or the partner's) counts as "current"
/// before the UI treats it as gone — also the freshness half of the "met"
/// gate below. Sized around realtime-subscription latency (~100-400ms per
/// the feature brief) plus a little slack, so a moment's network hiccup
/// doesn't make a held-still thumb visibly flicker away.
// 2.5s: sized around realtime latency PLUS delivery jitter — 1.5s flickered
// whenever two SSE messages arrived slightly far apart (user-reported).
const touchFreshWindow = Duration(milliseconds: 2500);

/// Normalized-distance threshold under which two fingertips count as
/// "touching" for the met moment. 0.15 of the touch area's side — close
/// enough to feel deliberate, loose enough that realtime jitter and two
/// real thumbs (never pixel-perfect) still meet.
const metDistanceThreshold = 0.15;

/// Whether enough time has passed since [lastSentAt] to send another touch
/// update right now. A null [lastSentAt] (nothing sent yet this press)
/// always sends immediately — the first frame of a press shouldn't wait.
bool shouldSendTouch({required DateTime? lastSentAt, required DateTime now}) {
  if (lastSentAt == null) return true;
  return !now.difference(lastSentAt).isNegative &&
      now.difference(lastSentAt) >= touchSendInterval;
}

/// Whether a touch reported at [at] still counts as current, as of [now].
bool isTouchFresh(DateTime at, DateTime now) {
  final age = now.difference(at);
  return !age.isNegative && age <= touchFreshWindow;
}

/// Straight-line distance between two normalized (0..1) points.
double touchDistance(Offset a, Offset b) => (a - b).distance;

/// The "met" gate: both fingertips present, both fresh as of [now], and
/// within [metDistanceThreshold] of each other.
bool didMeet({
  required Offset? mine,
  required DateTime? mineAt,
  required Offset? theirs,
  required DateTime? theirsAt,
  required DateTime now,
}) {
  if (mine == null || theirs == null) return false;
  if (mineAt == null || theirsAt == null) return false;
  if (!isTouchFresh(mineAt, now) || !isTouchFresh(theirsAt, now)) return false;
  return touchDistance(mine, theirs) <= metDistanceThreshold;
}

/// The three things a ping can be (server: `pings.kind`, a select field —
/// see server/migrations/13_pings.go).
///
/// A ping carries nothing else: no text, no photo, no read receipt. That's
/// the feature (kb/features.md, "One-tap 'thinking of you' ping — zero-effort
/// connection"): the cheapest possible way to say *I thought about you just
/// now*, so cheap that you actually send it.
enum PingKind {
  /// The default, and the one the big button sends without asking.
  thinking('thinking', '♡︎', 'thinking of you'),
  kiss('kiss', '(´ε｀ )♡︎', 'a kiss'),
  hug('hug', '(づ￣ ³￣)づ', 'a hug');

  const PingKind(this.id, this.kaomoji, this.label);

  /// Wire value. Never localize this — it's the server's enum.
  final String id;

  /// The face of the thing, per design-language.md's "kaomoji as voice".
  /// U+FE0E (text presentation selector) on the hearts keeps Android from
  /// swapping in a colour emoji glyph — same trick as the rest of the app.
  final String kaomoji;

  /// Short human name, sentence case, for buttons and notification bodies.
  final String label;

  /// Unknown ids (an older client, a hand-written record) fall back to
  /// [thinking] rather than throwing: a ping we can't quite name is still a
  /// ping, and the point is that it arrived.
  static PingKind byId(String id) => PingKind.values.firstWhere(
    (k) => k.id == id,
    orElse: () => PingKind.thinking,
  );
}

/// One ping, as stored. Immutable server-side (no update rule) and purged
/// after a week, so this model is read-once-and-react rather than something
/// the app keeps a long list of.
class Ping {
  const Ping({
    required this.id,
    required this.coupleId,
    required this.fromId,
    required this.kind,
    required this.created,
  });

  final String id;
  final String coupleId;

  /// Who sent it. The server guarantees `from = @request.auth.id` at create
  /// time, so this is trustworthy — which is what lets the notifier treat
  /// "fromId != me" as "my partner sent this" without a second lookup.
  final String fromId;

  final PingKind kind;
  final DateTime created;
}

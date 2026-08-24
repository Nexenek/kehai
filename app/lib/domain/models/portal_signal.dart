/// The seven things a portal signal can be (server: `portal_signals.kind`,
/// a select field — see server/migrations/16_portal.go). The wire values
/// must stay exactly in step with that list.
///
/// Three of them are the *human* half of the handshake — someone taps at the
/// window ([knock]), the other side lets them in ([accept]) or doesn't
/// ([decline]) — and three are the machinery WebRTC needs once both people
/// have said yes ([offer]/[answer]/[ice]). [hangup] drops the curtain on
/// both sides at once.
enum PortalSignalKind {
  knock('knock'),
  accept('accept'),
  decline('decline'),
  offer('offer'),
  answer('answer'),
  ice('ice'),
  hangup('hangup');

  const PortalSignalKind(this.id);

  /// Wire value. Never localize — it's the server's enum.
  final String id;

  /// Unknown ids answer null rather than falling back to something (the way
  /// `PingKind.byId` can fall back to "a ping is a ping"). A signal whose
  /// kind we don't recognise is a newer client talking about machinery this
  /// build has no idea how to run — the only safe reading is "ignore it".
  static PortalSignalKind? byId(String id) {
    for (final kind in PortalSignalKind.values) {
      if (kind.id == id) return kind;
    }
    return null;
  }
}

/// One signal, as stored. Immutable server-side (no update rule) and purged
/// after an hour, so — like `Ping` — this is a read-once-and-react model,
/// never a list the app keeps.
class PortalSignal {
  const PortalSignal({
    required this.id,
    required this.fromId,
    required this.kind,
    required this.payload,
    required this.created,
  });

  final String id;

  /// Who sent it. The server enforces `from = @request.auth.id` at create
  /// time, so this is trustworthy — which is what lets the engine treat
  /// "fromId != me" as "my partner" without a second lookup, and what makes
  /// the offerer/answerer role decision safe to base on it.
  final String fromId;

  final PortalSignalKind kind;

  /// Kind-specific body: `{sdp, type}` for offer/answer, `{candidate,
  /// sdpMid, sdpMLineIndex}` for ice, empty for the human signals. Left as
  /// a raw map on purpose — these shapes are WebRTC's, not ours, and the
  /// engine hands them almost straight to the peer connection.
  final Map<String, dynamic> payload;

  final DateTime created;
}

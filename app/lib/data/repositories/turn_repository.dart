import 'package:pocketbase/pocketbase.dart';

/// `GET /api/turn` — the ICE server list for a portal call (see
/// server/portal.go). The server answers
/// `{"iceServers": [{urls, username, credential}]}`, freshly HMAC-signed
/// per request, or an empty list when the home server has no coturn
/// configured (`KEHAI_TURN_SECRET` unset — off by default like every
/// optional service).
///
/// An empty list is a perfectly good answer, not an error: it means "no
/// relay, use host candidates", which is all a Tailscale-to-Tailscale pair
/// ever needs.
///
/// NOTE — no third-party STUN fallback, on purpose. Every public STUN
/// server (stun.l.google.com and friends) is a machine outside the couple's
/// control that gets told, on every call, that these two IP addresses are
/// talking to each other right now. That's exactly the metadata this app
/// exists to keep at home, and it buys nothing on the default path: inside
/// a tailnet the peers already have routable addresses, and outside one the
/// self-hosted TURN relay above is the answer. If a future wave wants
/// reflexive candidates without a relay, the right move is a coturn in
/// STUN-only mode on the same home server, not somebody else's.
class TurnRepository {
  TurnRepository(this._pb);

  final PocketBase _pb;

  /// Fetches the ICE server maps in the shape `RTCPeerConnection` wants
  /// them. A failed or malformed response answers an empty list rather than
  /// throwing: not being able to reach the TURN endpoint must never be what
  /// stops a call that host candidates could have carried.
  Future<List<Map<String, dynamic>>> fetchIceServers() async {
    try {
      final body = await _pb.send<Map<String, dynamic>>(
        '/api/turn',
        method: 'GET',
      );
      final raw = body['iceServers'];
      if (raw is! List) return const [];
      return raw.whereType<Map<String, dynamic>>().toList(growable: false);
    } catch (_) {
      return const [];
    }
  }
}

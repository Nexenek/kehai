import 'dart:async';

/// "Can we see the server right now?", asked on a loop.
///
/// Kehai's server is somebody's home machine reached over a tailnet, so
/// "offline" is the normal, temporary, uninteresting state it spends the
/// first few seconds of every login in — the app autostarts before the
/// network is up. Nothing about the app should *stop* because of that (see
/// [AppController.init]'s note on never gating startup on reachability);
/// the app just wants to know, so it can say so quietly and so it can give
/// the once-only things a nudge the moment the server turns up again.
///
/// Two cadences, because the two states want opposite things: while
/// offline, ask often ([offlineInterval]) so the way back is short; while
/// online, ask rarely ([onlineInterval]) so a healthy session isn't
/// spending a request a second on a question it already knows the answer
/// to. Every probe is capped at [probeTimeout] — a server that has gone
/// away usually doesn't refuse a connection, it simply never answers, and
/// an un-capped health check would hold the loop open indefinitely.
///
/// Pure scheduling, no PocketBase import: the caller hands in [probe] — a
/// future that completes for "reachable" and throws for anything else,
/// which is exactly the shape of `pb.health.check()` — which is what makes
/// this testable with `fakeAsync` and no server at all (see
/// connectivity_monitor_test.dart). Timer-driven throughout, never
/// `DateTime.now()`.
class ConnectivityMonitor {
  ConnectivityMonitor({
    required Future<void> Function() probe,
    required void Function(bool online) onChanged,
    bool online = true,
  }) : _probe = probe,
       _onChanged = onChanged,
       _online = online;

  /// How often to knock while the server isn't answering.
  static const offlineInterval = Duration(seconds: 10);

  /// How often to check that a working connection still works.
  static const onlineInterval = Duration(seconds: 60);

  /// How long one probe gets before it counts as a miss.
  static const probeTimeout = Duration(seconds: 5);

  final Future<void> Function() _probe;
  final void Function(bool online) _onChanged;

  bool _online;
  bool _running = false;
  bool _probing = false;
  Timer? _timer;

  /// Whether the last answer was "yes". Starts at whatever the constructor
  /// was told — `true` by default, the optimistic reading, so a normal
  /// launch never flashes an offline badge in the second before the first
  /// probe comes back.
  bool get isOnline => _online;

  bool get isRunning => _running;

  /// The gap before the next probe, given where we stand.
  Duration get interval => _online ? onlineInterval : offlineInterval;

  /// Starts the loop with an immediate probe — at boot the current state is
  /// a guess, and the whole point is to replace it with an answer quickly.
  /// Idempotent: starting an already-running monitor does nothing.
  void start() {
    if (_running) return;
    _running = true;
    unawaited(checkNow());
  }

  /// Stops the loop. The remembered [isOnline] is left alone — stopping is
  /// not the same as going offline.
  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  /// Records an answer the caller already has in hand — the health check
  /// [AppController.confirmServer] just did, say — rather than spending a
  /// probe re-asking. Reschedules the next tick at the new cadence.
  void report(bool online) {
    _apply(online);
    if (_running) _schedule();
  }

  /// One probe, now, then back onto the schedule. Safe to call at any time;
  /// a probe already in flight is left to finish rather than doubled up.
  Future<void> checkNow() async {
    if (!_running || _probing) return;
    _probing = true;
    final ok = await _probeOnce();
    _probing = false;
    // Stopped (or disposed) while the probe was in the air: honour that
    // rather than reporting a state nobody asked for and re-arming a timer
    // nobody wants.
    if (!_running) return;
    _apply(ok);
    _schedule();
  }

  Future<bool> _probeOnce() async {
    try {
      await _probe().timeout(probeTimeout);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _apply(bool online) {
    if (_online == online) return;
    _online = online;
    _onChanged(online);
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(interval, () => unawaited(checkNow()));
  }

  void dispose() => stop();
}

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:pocketbase/pocketbase.dart';

import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/ping_repository.dart';
import '../../../data/services/notifications/notification_hub.dart';
import '../../../domain/models/ping.dart';
import 'ping_send_logic.dart';

/// Drives the "thinking of you" button and the pings coming the other way.
///
/// Sending is optimistic and deliberately consequence-free: the flourish
/// fires the moment you tap, and a failed send is swallowed rather than
/// surfaced. A ping that didn't reach the server is worth exactly one
/// re-tap — an error dialog about it would make the lightest gesture in the
/// app feel heavy.
class PingViewModel extends ChangeNotifier {
  PingViewModel({
    required AuthRepository authRepository,
    required PingRepository pingRepository,
    KehaiNotifications? notifications,
    @visibleForTesting DateTime Function()? now,
  }) : _authRepository = authRepository,
       _pingRepository = pingRepository,
       _notifications = notifications,
       _now = now ?? DateTime.now;

  final AuthRepository _authRepository;
  final PingRepository _pingRepository;
  final KehaiNotifications? _notifications;
  final DateTime Function() _now;

  /// True while the "sent ♡" flourish is on screen.
  bool justSent = false;

  /// The most recent ping my partner sent me this session, or null. The
  /// partner card shows it as a small, quiet line — a ping is a moment, and
  /// a permanent list of moments is a different (worse) feature.
  Ping? lastReceived;

  DateTime? _lastSentAt;
  Timer? _flourishTimer;
  Timer? _receivedTimer;
  UnsubscribeFunc? _unsub;
  String? _partnerId;

  String? get _coupleId => _authRepository.coupleId;
  String get _myId => _authRepository.currentUserId;

  /// Whether a tap right now would actually send. The button greys out on
  /// this, so the debounce is visible rather than mysterious.
  bool get canSend =>
      _coupleId != null &&
      shouldSendPing(now: _now(), lastSentAt: _lastSentAt);

  Future<void> init() async {
    _unsub = await _pingRepository.subscribe(_onPing);
  }

  /// Called by the home screen once the partner is known — same late-binding
  /// shape as [DoodleViewModel.updatePartner].
  void updatePartner(String? partnerId) {
    if (partnerId == _partnerId) return;
    _partnerId = partnerId;
    if (partnerId == null) {
      lastReceived = null;
      notifyListeners();
    }
  }

  void _onPing(Ping ping) {
    if (ping.coupleId != _coupleId) return;
    // My own ping echoing back off the realtime channel — the flourish
    // already happened locally when I tapped.
    if (ping.fromId == _myId) return;

    lastReceived = ping;
    notifyListeners();

    // The received line fades on its own: it's an arrival, not an inbox.
    _receivedTimer?.cancel();
    _receivedTimer = Timer(const Duration(seconds: 30), () {
      lastReceived = null;
      notifyListeners();
    });

    _notifications?.report(
      () => _notifications.reportPing(fromId: ping.fromId, kind: ping.kind),
    );
  }

  /// Sends [kind], unless the debounce says otherwise. Returns whether it
  /// went (used by the widget test; callers in the UI ignore it and just
  /// watch [justSent]).
  Future<bool> send([PingKind kind = PingKind.thinking]) async {
    final coupleId = _coupleId;
    if (coupleId == null) return false;
    if (!shouldSendPing(now: _now(), lastSentAt: _lastSentAt)) return false;

    _lastSentAt = _now();
    justSent = true;
    notifyListeners();

    _flourishTimer?.cancel();
    _flourishTimer = Timer(pingSentFlourish, () {
      justSent = false;
      notifyListeners();
    });
    // Re-enable the button the moment the debounce lapses, without waiting
    // for a rebuild triggered by something else.
    Timer(pingDebounce, () {
      if (hasListeners) notifyListeners();
    });

    try {
      await _pingRepository.send(
        coupleId: coupleId,
        fromId: _myId,
        kind: kind,
      );
    } catch (_) {
      // Swallowed on purpose — see the class doc.
    }
    return true;
  }

  @override
  void dispose() {
    _flourishTimer?.cancel();
    _receivedTimer?.cancel();
    _unsub?.call();
    super.dispose();
  }
}

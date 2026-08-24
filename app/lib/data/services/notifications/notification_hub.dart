import 'dart:async';

import '../../../domain/models/ping.dart';
import 'app_focus.dart';
import 'kehai_sound.dart';
import 'notification_decision.dart';

/// The one place the app's realtime subscriptions hand events to the
/// notifier.
///
/// ## Why this shape and not an event bus
///
/// The obvious alternative was a broadcast `StreamController` that every view
/// model publishes into. It was rejected for two reasons:
///
/// 1. Every producer already *has* a place to call from — each view model
///    owns exactly one realtime subscription and knows, right there, who
///    authored the record it just received. A stream would add an
///    indirection whose only job is to lose that context.
/// 2. A stream makes ordering and lifetime fuzzy in a way that matters here:
///    notifications are side effects, and a side effect that fires after the
///    view model was disposed (or twice, because two screens subscribed) is
///    the exact failure mode we don't want. A plain object with a method is
///    trivially "call it or don't".
///
/// So: one long-lived object hanging off [AppController], handed to the view
/// models that can produce events. Null in every test that doesn't care.
///
/// ## Who calls it
///
/// - **Desktop**: the UI isolate's view models ([PingViewModel],
///   [DoodleViewModel], [InstantsViewModel], [QuestionsViewModel]).
/// - **Android**: [KehaiTaskHandler] in the foreground-service isolate, which
///   subscribes to the same collections and keeps working with the app
///   closed. The UI isolate's own view models are muted there ([enabled] is
///   set false once presence has been handed off) so a ping doesn't notify
///   twice — the same single-writer rule the heartbeat and location
///   publisher already follow.
class KehaiNotifications {
  KehaiNotifications({required this.notifier, this.focus});

  /// Typed as the one-method [NotificationSink] rather than the concrete
  /// [KehaiNotifier] so a test can hand this a recorder. In the app it is
  /// always a real [KehaiNotifier].
  final NotificationSink notifier;

  /// Whether the user is currently looking at Kehai on this device. Null (the
  /// background isolate's case) means "no window here to be looking at" —
  /// [KehaiTaskHandler] tracks the app's foreground state separately and
  /// passes it in via [foregroundOverride].
  final AppFocusTracker? focus;

  /// My own user id, so the self-echo rule works. Set once the session is
  /// known; while it's empty every event is treated as somebody else's, which
  /// is the safe direction (a stray notification beats a silent one).
  String myUserId = '';

  /// The partner's display name for the headline. Empty falls back to
  /// "your person".
  String partnerName = '';

  /// Master switch for this isolate. See the class doc — on Android the UI
  /// isolate turns itself off once the foreground service takes over.
  bool enabled = true;

  /// Used by the background isolate, which has no window: it learns the app's
  /// foreground state from the UI isolate over `sendDataToTask` instead.
  bool? foregroundOverride;

  bool get _appInForeground =>
      foregroundOverride ?? focus?.isForeground.value ?? false;

  /// A ping landed. [fromId] is the ping's `from` — the server guarantees it's
  /// genuinely who it says.
  Future<void> reportPing({required String fromId, required PingKind kind}) =>
      _report(
        KehaiEvent(
          kind: KehaiEventKind.ping,
          authorId: fromId,
          partnerName: partnerName,
          pingKind: kind,
        ),
      );

  Future<void> reportDoodle({required String authorId}) => _report(
    KehaiEvent(
      kind: KehaiEventKind.doodle,
      authorId: authorId,
      partnerName: partnerName,
    ),
  );

  Future<void> reportInstant({required String authorId}) => _report(
    KehaiEvent(
      kind: KehaiEventKind.instant,
      authorId: authorId,
      partnerName: partnerName,
    ),
  );

  /// The daily question just flipped to `both_answered` — i.e. the partner
  /// answered, since our own answer can't be the one that surprises us.
  /// [partnerId] is passed rather than assumed so the self-echo rule still
  /// has something real to compare against.
  Future<void> reportReveal({required String partnerId}) => _report(
    KehaiEvent(
      kind: KehaiEventKind.reveal,
      authorId: partnerId,
      partnerName: partnerName,
    ),
  );

  /// Someone's at the window. [fromId] is the knock signal's `from`, which
  /// both the FGS-isolate subscription and [PortalKnockBridge] only ever
  /// hand over after dropping their own account's echo — see
  /// [PortalSignalRepository.subscribe] — so by the time this is called it
  /// is already known to be the partner's.
  Future<void> reportKnock({required String fromId}) => _report(
    KehaiEvent(
      kind: KehaiEventKind.knock,
      authorId: fromId,
      partnerName: partnerName,
    ),
  );

  Future<void> _report(KehaiEvent event) async {
    if (!enabled) return;
    final request = decideNotification(
      event: event,
      myUserId: myUserId,
      appInForeground: _appInForeground,
    );
    if (request == null) return;
    await notifier.notify(request);
  }

  /// Fire-and-forget wrapper for call sites inside realtime callbacks, which
  /// are synchronous `void` handlers.
  void report(Future<void> Function() send) => unawaited(send());
}

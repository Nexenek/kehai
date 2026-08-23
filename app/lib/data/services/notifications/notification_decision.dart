import '../../../domain/models/ping.dart';
import '../../../ui/core/strings/app_strings.dart';
import 'kehai_sound.dart';

/// Something that happened in the couple, as far as the notifier cares.
///
/// Every field the decision needs is on here, so [decideNotification] is a
/// pure function of its arguments — no repositories, no plugins, no clock.
/// That's the whole reason this file exists separately from
/// `kehai_notifier.dart`: the interesting rules (don't echo yourself, don't
/// interrupt someone who's already looking, say the right thing per kind)
/// are unit-testable without a platform channel in sight.
class KehaiEvent {
  const KehaiEvent({
    required this.kind,
    required this.authorId,
    this.partnerName = '',
    this.pingKind,
  });

  final KehaiEventKind kind;

  /// Whoever caused it — the ping's `from`, the doodle's/instant's `author`,
  /// or the partner whose answer completed the daily question.
  final String authorId;

  /// Their display name, for the headline. Empty is fine and handled.
  final String partnerName;

  /// Only meaningful for [KehaiEventKind.ping]; picks the body copy.
  final PingKind? pingKind;
}

/// Whatever actually puts a notification on screen.
///
/// One method, so [KehaiNotifications] can be exercised in a test with a
/// recording fake instead of a real plugin — the alternative was making the
/// gating rules untestable, and they're the part most worth testing.
/// [KehaiNotifier] is the only real implementation.
abstract interface class NotificationSink {
  Future<void> notify(NotificationRequest request);
}

/// A notification we've decided to actually raise.
class NotificationRequest {
  const NotificationRequest({
    required this.eventKind,
    required this.title,
    required this.body,
  });

  final KehaiEventKind eventKind;
  final String title;
  final String body;

  @override
  bool operator ==(Object other) =>
      other is NotificationRequest &&
      other.eventKind == eventKind &&
      other.title == title &&
      other.body == body;

  @override
  int get hashCode => Object.hash(eventKind, title, body);

  @override
  String toString() => 'NotificationRequest($eventKind, "$title", "$body")';
}

/// Decides whether [event] should become a notification on THIS device, and
/// what it should say. Returns null for "stay quiet".
///
/// Two suppression rules, both of which exist because the alternative is
/// annoying rather than because of any platform limitation:
///
/// 1. **Never echo yourself.** Every realtime subscription in the app also
///    delivers your own writes back to you (that's how the other devices you
///    own stay in sync). Sending your partner a kiss from your phone must not
///    buzz your own phone a heartbeat later.
///
/// 2. **Never interrupt someone who's already looking.** If Kehai is the
///    focused window on this desktop, or resumed in the foreground on this
///    phone, you are literally watching the doodle arrive — a notification
///    about it is pure noise, and the in-app flourish already told you.
///    (This is per-device by design: your phone still buzzes for a ping you
///    received while sitting at the desktop, which is exactly right — you may
///    walk away from the desk.)
///
/// Everything else is copy. Voice per kb/design-language.md: warm, plain,
/// sentence case, kaomoji doing the emotional work.
NotificationRequest? decideNotification({
  required KehaiEvent event,
  required String myUserId,
  required bool appInForeground,
}) {
  // Rule 1. An empty authorId means "we don't know who did this", which we
  // treat as not-me rather than dropping the event — an unattributed doodle
  // still arrived, and the alternative (silence) is the worse failure.
  if (event.authorId.isNotEmpty && event.authorId == myUserId) return null;

  // Rule 2.
  if (appInForeground) return null;

  final name = event.partnerName.trim().isEmpty
      ? AppStrings.notifyFallbackName
      : event.partnerName.trim();

  return switch (event.kind) {
    KehaiEventKind.ping => NotificationRequest(
      eventKind: KehaiEventKind.ping,
      title: AppStrings.notifyPingTitle(name),
      body: AppStrings.notifyPingBody(event.pingKind ?? PingKind.thinking),
    ),
    KehaiEventKind.doodle => NotificationRequest(
      eventKind: KehaiEventKind.doodle,
      title: AppStrings.notifyDoodleTitle(name),
      body: AppStrings.notifyDoodleBody,
    ),
    KehaiEventKind.instant => NotificationRequest(
      eventKind: KehaiEventKind.instant,
      title: AppStrings.notifyInstantTitle(name),
      body: AppStrings.notifyInstantBody,
    ),
    KehaiEventKind.reveal => NotificationRequest(
      eventKind: KehaiEventKind.reveal,
      title: AppStrings.notifyRevealTitle,
      body: AppStrings.notifyRevealBody(name),
    ),
  };
}

import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/data/services/notifications/kehai_sound.dart';
import 'package:couples_app/data/services/notifications/notification_decision.dart';
import 'package:couples_app/data/services/notifications/notification_hub.dart';
import 'package:couples_app/domain/models/ping.dart';

/// Records what would have reached the screen — the reason [NotificationSink]
/// exists as a one-method interface.
class _Recorder implements NotificationSink {
  final List<NotificationRequest> raised = [];

  @override
  Future<void> notify(NotificationRequest request) async => raised.add(request);
}

void main() {
  late _Recorder sink;
  late KehaiNotifications hub;

  setUp(() {
    sink = _Recorder();
    hub = KehaiNotifications(notifier: sink)
      ..myUserId = 'me'
      ..partnerName = 'mati'
      ..foregroundOverride = false;
  });

  test('a partner ping reaches the sink with its kind', () async {
    await hub.reportPing(fromId: 'them', kind: PingKind.hug);
    expect(sink.raised, hasLength(1));
    expect(sink.raised.single.eventKind, KehaiEventKind.ping);
    expect(sink.raised.single.body, contains('hug'));
  });

  test('my own ping echoing back is dropped', () async {
    await hub.reportPing(fromId: 'me', kind: PingKind.thinking);
    expect(sink.raised, isEmpty);
  });

  test('nothing is raised while the app is on screen', () async {
    hub.foregroundOverride = true;
    await hub.reportDoodle(authorId: 'them');
    await hub.reportInstant(authorId: 'them');
    await hub.reportReveal(partnerId: 'them');
    expect(sink.raised, isEmpty);
  });

  test('the master switch mutes this isolate entirely', () async {
    // The Android case: the foreground service owns the subscriptions, so
    // the UI isolate must not raise a second copy of everything.
    hub.enabled = false;
    await hub.reportPing(fromId: 'them', kind: PingKind.kiss);
    await hub.reportDoodle(authorId: 'them');
    expect(sink.raised, isEmpty);
  });

  test('the headline follows the partner name as it becomes known', () async {
    hub.partnerName = '';
    await hub.reportInstant(authorId: 'them');
    expect(sink.raised.single.title, contains('your person'));

    hub.partnerName = 'mati';
    await hub.reportInstant(authorId: 'them');
    expect(sink.raised.last.title, contains('mati'));
  });

  test('with no focus tracker and no override, we assume not-foreground', () {
    // The background isolate's starting position: it has no window to watch,
    // so silence would be the wrong default.
    final bare = KehaiNotifications(notifier: sink)..myUserId = 'me';
    expect(bare.foregroundOverride, isNull);
    return expectLater(
      bare.reportDoodle(authorId: 'them').then((_) => sink.raised.length),
      completion(1),
    );
  });
}

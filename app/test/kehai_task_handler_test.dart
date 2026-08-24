import 'package:clock/clock.dart';
import 'package:couples_app/data/services/background/kehai_task_handler.dart';
import 'package:couples_app/data/services/notifications/kehai_sound.dart';
import 'package:couples_app/data/services/notifications/notification_decision.dart';
import 'package:couples_app/data/services/notifications/notification_hub.dart';
import 'package:couples_app/data/services/presence/android/android_presence_service.dart';
import 'package:couples_app/data/services/presence/android/vitals_service.dart';
import 'package:couples_app/data/services/prefs_service.dart';
import 'package:couples_app/domain/models/portal_signal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Recorder implements NotificationSink {
  final List<NotificationRequest> raised = [];

  @override
  Future<void> notify(NotificationRequest request) async => raised.add(request);
}

/// Regression coverage for the bug this pass fixes (kb/features.md
/// "Focused-app status"): `KehaiTaskHandler` re-applied `shareLocation` on
/// every tick, but never `shareFocusedApp`/`shareUnknownApps` — those
/// toggles could be flipped from the superpowers screen and the background
/// isolate (the one actually posting the partner's status once the app is
/// backgrounded) would just never find out.
///
/// Exercised through the `@visibleForTesting` seams
/// (`presenceServiceForTest`, `applySharingPrefsForTest`) rather than
/// [KehaiTaskHandler.onStart]/[KehaiTaskHandler.onRepeatEvent] — those go
/// through real PocketBase/HeartbeatService wiring this test has no
/// business standing up.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('KehaiTaskHandler — sharing prefs re-apply', () {
    test(
      'pushes shareFocusedApp/shareUnknownApps onto an AndroidPresenceService',
      () async {
        SharedPreferences.setMockInitialValues({
          'share_focused_app': true,
          'share_unknown_apps': true,
        });
        final prefs = await PrefsService.create();

        final handler = KehaiTaskHandler();
        final presence = AndroidPresenceService();
        handler.presenceServiceForTest = presence;
        addTearDown(() => presence.dispose());

        expect(presence.shareFocusedApp, isFalse);
        expect(presence.shareUnknownApps, isFalse);

        await handler.applySharingPrefsForTest(prefs);

        expect(presence.shareFocusedApp, isTrue);
        expect(presence.shareUnknownApps, isTrue);
      },
    );

    test('turning both back off reaches the presence service too', () async {
      SharedPreferences.setMockInitialValues({
        'share_focused_app': true,
        'share_unknown_apps': true,
      });
      final firstPrefs = await PrefsService.create();
      // Flip them off through a *second* PrefsService instance, mirroring
      // the UI isolate writing while the background isolate's own
      // SharedPreferences instance still has the stale cached values —
      // exactly the bug `prefs.reload()` inside `_applySharingPrefs` exists
      // to fix.
      final uiIsolatePrefs = await PrefsService.create();
      await uiIsolatePrefs.setShareFocusedApp(false);
      await uiIsolatePrefs.setShareUnknownApps(false);

      final handler = KehaiTaskHandler();
      final presence = AndroidPresenceService();
      handler.presenceServiceForTest = presence;
      addTearDown(() => presence.dispose());
      presence.shareFocusedApp = true;
      presence.shareUnknownApps = true;

      await handler.applySharingPrefsForTest(firstPrefs);

      expect(presence.shareFocusedApp, isFalse);
      expect(presence.shareUnknownApps, isFalse);
    });

    test(
      'a non-Android presence service is left alone (no crash, no-op)',
      () async {
        SharedPreferences.setMockInitialValues({'share_focused_app': true});
        final prefs = await PrefsService.create();

        final handler = KehaiTaskHandler();
        // No presenceServiceForTest set at all — _presenceService stays
        // null, same as a handler that never got past `_connect`'s early
        // returns.
        await handler.applySharingPrefsForTest(prefs);
        // No assertion beyond "didn't throw" — this is the "no server
        // saved yet" / "not Android" path, both of which must stay silent.
      },
    );

    test('onReceiveData applies the current prefs once', () async {
      SharedPreferences.setMockInitialValues({
        'share_focused_app': true,
        'share_unknown_apps': false,
      });

      final handler = KehaiTaskHandler();
      final presence = AndroidPresenceService();
      handler.presenceServiceForTest = presence;
      addTearDown(() => presence.dispose());

      handler.onReceiveData('anything — the payload is never read');
      // onReceiveData fires the re-apply unawaited; let it settle.
      await Future<void>.delayed(Duration.zero);

      expect(presence.shareFocusedApp, isTrue);
      expect(presence.shareUnknownApps, isFalse);
    });
  });

  /// `shareVitals` (kb/platform-android.md "Steps / heart rate") joins the
  /// same re-apply, for the same reason: the toggle is flipped in the UI
  /// isolate, but it's the background isolate that actually reads Health
  /// Connect once the app is off screen.
  group('KehaiTaskHandler — shareVitals re-apply', () {
    test('pushes shareVitals onto the VitalsService', () async {
      SharedPreferences.setMockInitialValues({'share_vitals': true});
      final prefs = await PrefsService.create();

      final handler = KehaiTaskHandler();
      final vitals = VitalsService(isSupported: true);
      handler.vitalsServiceForTest = vitals;

      expect(vitals.enabled, isFalse);
      await handler.applySharingPrefsForTest(prefs);
      expect(vitals.enabled, isTrue);
    });

    test(
      'turning it off reaches the service through the stale cache',
      () async {
        SharedPreferences.setMockInitialValues({'share_vitals': true});
        final backgroundPrefs = await PrefsService.create();
        final uiIsolatePrefs = await PrefsService.create();
        await uiIsolatePrefs.setShareVitals(false);

        final handler = KehaiTaskHandler();
        final vitals = VitalsService(isSupported: true)..enabled = true;
        handler.vitalsServiceForTest = vitals;

        await handler.applySharingPrefsForTest(backgroundPrefs);

        expect(vitals.enabled, isFalse);
      },
    );

    test('defaults off when nothing was ever saved', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await PrefsService.create();

      final handler = KehaiTaskHandler();
      final vitals = VitalsService(isSupported: true)..enabled = true;
      handler.vitalsServiceForTest = vitals;

      await handler.applySharingPrefsForTest(prefs);

      expect(vitals.enabled, isFalse);
    });
  });

  /// Portal knocks (kb/roadmap.md Phase 7 curtain): exercised through
  /// [KehaiTaskHandler.handlePortalSignalForTest] — the exact handler the
  /// real `portal_signals` subscription wires to — rather than
  /// [KehaiTaskHandler.onStart], which needs the live PocketBase/realtime
  /// wiring this test has no business standing up (same reasoning as every
  /// other group in this file).
  group('KehaiTaskHandler — portal knock notifications', () {
    PortalSignal knock({DateTime? created, String from = 'partner'}) =>
        PortalSignal(
          id: 'sig1',
          fromId: from,
          kind: PortalSignalKind.knock,
          payload: const {},
          created: created ?? clock.now(),
        );

    test('a fresh knock is reported as KehaiEventKind.knock', () {
      final handler = KehaiTaskHandler();
      final sink = _Recorder();
      handler.notificationsForTest = KehaiNotifications(notifier: sink)
        ..myUserId = 'me'
        ..partnerName = 'kai'
        ..foregroundOverride = false;

      handler.handlePortalSignalForTest(knock());

      expect(sink.raised, hasLength(1));
      expect(sink.raised.single.eventKind, KehaiEventKind.knock);
    });

    test('a stale knock (redelivered on reconnect) is not reported', () {
      final handler = KehaiTaskHandler();
      final sink = _Recorder();
      handler.notificationsForTest = KehaiNotifications(notifier: sink)
        ..myUserId = 'me'
        ..foregroundOverride = false;

      handler.handlePortalSignalForTest(
        knock(created: clock.now().subtract(const Duration(minutes: 20))),
      );

      expect(sink.raised, isEmpty);
    });

    test('non-knock signals (offer/answer/ice/accept/…) are ignored', () {
      final handler = KehaiTaskHandler();
      final sink = _Recorder();
      handler.notificationsForTest = KehaiNotifications(notifier: sink)
        ..myUserId = 'me'
        ..foregroundOverride = false;

      for (final kind in [
        PortalSignalKind.accept,
        PortalSignalKind.decline,
        PortalSignalKind.offer,
        PortalSignalKind.answer,
        PortalSignalKind.ice,
        PortalSignalKind.hangup,
      ]) {
        handler.handlePortalSignalForTest(
          PortalSignal(
            id: 'sig',
            fromId: 'partner',
            kind: kind,
            payload: const {},
            created: clock.now(),
          ),
        );
      }

      expect(sink.raised, isEmpty);
    });

    test('with no notifications set yet, handling a knock does not crash', () {
      final handler = KehaiTaskHandler();
      // No notificationsForTest — mirrors a signal arriving before
      // [KehaiTaskHandler._connect] finished building the notifier.
      handler.handlePortalSignalForTest(knock());
    });
  });
}

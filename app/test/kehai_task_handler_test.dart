import 'package:couples_app/data/services/background/kehai_task_handler.dart';
import 'package:couples_app/data/services/presence/android/android_presence_service.dart';
import 'package:couples_app/data/services/presence/android/vitals_service.dart';
import 'package:couples_app/data/services/prefs_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
}

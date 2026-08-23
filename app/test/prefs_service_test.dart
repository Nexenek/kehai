import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:couples_app/data/services/prefs_service.dart';

void main() {
  group('PrefsService — focused-app sharing opt-ins', () {
    test('shareFocusedApp defaults to off', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await PrefsService.create();
      expect(prefs.shareFocusedApp, isFalse);
    });

    test('shareUnknownApps defaults to off', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await PrefsService.create();
      expect(prefs.shareUnknownApps, isFalse);
    });

    test('setShareFocusedApp persists across a fresh PrefsService', () async {
      SharedPreferences.setMockInitialValues({});
      final first = await PrefsService.create();
      await first.setShareFocusedApp(true);

      final reloaded = await PrefsService.create();
      expect(reloaded.shareFocusedApp, isTrue);
    });

    test('setShareUnknownApps persists across a fresh PrefsService', () async {
      SharedPreferences.setMockInitialValues({});
      final first = await PrefsService.create();
      await first.setShareUnknownApps(true);

      final reloaded = await PrefsService.create();
      expect(reloaded.shareUnknownApps, isTrue);
    });

    test('the two opt-ins are independent', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await PrefsService.create();
      await prefs.setShareFocusedApp(true);

      expect(prefs.shareFocusedApp, isTrue);
      expect(prefs.shareUnknownApps, isFalse);
    });

    test('turning shareFocusedApp back off persists too', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await PrefsService.create();
      await prefs.setShareFocusedApp(true);
      await prefs.setShareFocusedApp(false);

      final reloaded = await PrefsService.create();
      expect(reloaded.shareFocusedApp, isFalse);
    });
  });

  group('PrefsService — shareLocation opt-in', () {
    test('defaults to off', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await PrefsService.create();
      expect(prefs.shareLocation, isFalse);
    });

    test('setShareLocation persists across a fresh PrefsService', () async {
      SharedPreferences.setMockInitialValues({});
      final first = await PrefsService.create();
      await first.setShareLocation(true);

      final reloaded = await PrefsService.create();
      expect(reloaded.shareLocation, isTrue);
    });

    test('turning it back off persists too', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await PrefsService.create();
      await prefs.setShareLocation(true);
      await prefs.setShareLocation(false);

      final reloaded = await PrefsService.create();
      expect(reloaded.shareLocation, isFalse);
    });

    test('independent of the focused-app opt-ins', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await PrefsService.create();
      await prefs.setShareLocation(true);

      expect(prefs.shareLocation, isTrue);
      expect(prefs.shareFocusedApp, isFalse);
      expect(prefs.shareUnknownApps, isFalse);
    });
  });
}

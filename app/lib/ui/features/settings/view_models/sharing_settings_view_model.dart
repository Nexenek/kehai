import 'package:flutter/foundation.dart';

/// State for the desktop "sharing ✧" window: the two focused-app opt-ins
/// (kb/features.md "Focused-app status").
///
/// Persistence and pushing the value into the live `WindowsPresenceService`
/// both live on `AppController` (the one place that owns the presence
/// service) — [onSetShareFocusedApp]/[onSetShareUnknownApps] are its
/// `setShareFocusedApp`/`setShareUnknownApps` methods, handed in as plain
/// callbacks so this class stays a thin, easily-fake-able wrapper instead
/// of duplicating that logic (mirrors `PhoneSuperpowersViewModel`'s
/// android-side toggles, same shape).
class SharingSettingsViewModel extends ChangeNotifier {
  SharingSettingsViewModel({
    required bool initialShareFocusedApp,
    required bool initialShareUnknownApps,
    required this.onSetShareFocusedApp,
    required this.onSetShareUnknownApps,
  }) {
    shareFocusedApp = initialShareFocusedApp;
    shareUnknownApps = initialShareUnknownApps;
  }

  final Future<void> Function(bool value) onSetShareFocusedApp;
  final Future<void> Function(bool value) onSetShareUnknownApps;

  bool shareFocusedApp = false;
  bool shareUnknownApps = false;

  Future<void> setShareFocusedApp(bool value) async {
    shareFocusedApp = value;
    await onSetShareFocusedApp(value);
    notifyListeners();
  }

  Future<void> setShareUnknownApps(bool value) async {
    shareUnknownApps = value;
    await onSetShareUnknownApps(value);
    notifyListeners();
  }
}

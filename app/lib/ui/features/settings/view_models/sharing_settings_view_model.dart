import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import '../../../../data/services/presence/linux_foreground_app_detector.dart';
import '../../../../data/services/presence/windows_presence_service.dart';
import '../../../../domain/activity_mapper.dart';
import '../../../core/strings/app_strings.dart';

/// State for the desktop "sharing ✧" window: the two focused-app opt-ins
/// (kb/features.md "Focused-app status") plus a live "what we'd share right
/// now" [preview] line.
///
/// Persistence and pushing the value into the live `WindowsPresenceService`
/// both live on `AppController` (the one place that owns the presence
/// service) — [onSetShareFocusedApp]/[onSetShareUnknownApps] are its
/// `setShareFocusedApp`/`setShareUnknownApps` methods, handed in as plain
/// callbacks so this class stays a thin, easily-fake-able wrapper instead
/// of duplicating that logic (mirrors `PhoneSuperpowersViewModel`'s
/// android-side toggles, same shape).
///
/// The preview exists because this feature has a genuinely silent failure
/// mode: turn the toggle on under GNOME Wayland (no window reader at all)
/// or with an app that has no `ActivityMapper` entry and `shareUnknownApps`
/// off, and nothing ever goes wrong loudly — the partner's card just never
/// says anything. [_refreshPreview] polls the same raw passthroughs the
/// live presence service uses (`WindowsPresenceService.getForegroundApp`,
/// `LinuxForegroundAppDetector.detect`) and runs them through the very same
/// [ActivityMapper] the real poll loop uses, so "what this preview says"
/// and "what actually gets shared" can never drift apart.
class SharingSettingsViewModel extends ChangeNotifier {
  SharingSettingsViewModel({
    required bool initialShareFocusedApp,
    required bool initialShareUnknownApps,
    required this.onSetShareFocusedApp,
    required this.onSetShareUnknownApps,
    @visibleForTesting WindowsPresenceService? windowsProbe,
    @visibleForTesting LinuxForegroundAppDetector? linuxProbe,
    @visibleForTesting Duration previewInterval = const Duration(seconds: 3),
  }) : _windowsProbe =
           windowsProbe ?? (Platform.isWindows ? WindowsPresenceService() : null),
       _linuxProbe =
           linuxProbe ?? (Platform.isLinux ? LinuxForegroundAppDetector() : null) {
    shareFocusedApp = initialShareFocusedApp;
    shareUnknownApps = initialShareUnknownApps;
    // Show something sensible before the first async probe lands, rather
    // than a blank line for a beat.
    preview = resolvePreviewMessage(
      shareFocusedApp: shareFocusedApp,
      hasReading: false,
      mappedLabel: null,
    );
    unawaited(_refreshPreview());
    _previewTimer = Timer.periodic(
      previewInterval,
      (_) => unawaited(_refreshPreview()),
    );
  }

  final Future<void> Function(bool value) onSetShareFocusedApp;
  final Future<void> Function(bool value) onSetShareUnknownApps;

  /// Null on any platform other than Windows (including in tests that
  /// don't inject one) — [_probe] then falls through to [_linuxProbe].
  final WindowsPresenceService? _windowsProbe;

  /// Null off Linux. `LinuxForegroundAppDetector.detect` has no side
  /// effects worth sharing with the live presence service's own instance,
  /// so this preview happily owns a second one.
  final LinuxForegroundAppDetector? _linuxProbe;

  Timer? _previewTimer;

  bool shareFocusedApp = false;
  bool shareUnknownApps = false;

  /// "What we'd share right now" — see the class doc comment.
  String preview = '';

  Future<void> setShareFocusedApp(bool value) async {
    shareFocusedApp = value;
    await onSetShareFocusedApp(value);
    notifyListeners();
    await _refreshPreview();
  }

  Future<void> setShareUnknownApps(bool value) async {
    shareUnknownApps = value;
    await onSetShareUnknownApps(value);
    notifyListeners();
    await _refreshPreview();
  }

  Future<void> _refreshPreview() async {
    final raw = await _probe();
    final mapped = raw == null ? null : _mapLabel(raw.identifier);
    final refined = ActivityMapper.refineBrowserLabel(mapped, raw?.title);
    final message = resolvePreviewMessage(
      shareFocusedApp: shareFocusedApp,
      hasReading: raw != null,
      mappedLabel: refined,
    );
    if (message == preview) return;
    preview = message;
    notifyListeners();
  }

  String? _mapLabel(String identifier) {
    if (_windowsProbe != null) {
      return ActivityMapper.mapWindowsExe(
        identifier,
        shareUnknown: shareUnknownApps,
      );
    }
    return ActivityMapper.mapLinuxClass(
      identifier,
      shareUnknown: shareUnknownApps,
    );
  }

  Future<({String identifier, String title})?> _probe() async {
    final windows = _windowsProbe;
    if (windows != null) {
      final app = await windows.getForegroundApp();
      if (app == null) return null;
      return (identifier: app.exe, title: app.title);
    }
    final linux = _linuxProbe;
    if (linux != null) {
      final window = await linux.detect();
      if (window == null) return null;
      return (identifier: window.wmClass, title: window.title);
    }
    // Neither probe exists: an unsupported desktop (or a platform this
    // preview genuinely has no reader for) — same "no reading" bucket a
    // failed live probe would land in.
    return null;
  }

  /// Pure resolution of the preview line from already-computed probe
  /// results — no platform channel, no I/O, no `Platform.is*` checks — so
  /// it's directly unit-testable against every state the toggles/probe can
  /// be in.
  @visibleForTesting
  static String resolvePreviewMessage({
    required bool shareFocusedApp,
    required bool hasReading,
    required String? mappedLabel,
  }) {
    if (!shareFocusedApp) return AppStrings.sharingPreviewOff;
    if (!hasReading) return AppStrings.sharingPreviewNoReading;
    if (mappedLabel == null) return AppStrings.sharingPreviewUnmapped;
    return AppStrings.sharingPreviewSharing(mappedLabel);
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    _previewTimer = null;
    super.dispose();
  }
}

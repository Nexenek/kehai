import 'dart:ui' show Offset, Rect;

import 'package:shared_preferences/shared_preferences.dart';

/// Thin wrapper around [SharedPreferences] for the handful of values we
/// persist outside the PocketBase auth store: the server URL and the last
/// invite-code the user was shown.
class PrefsService {
  PrefsService(this._prefs);

  static const _serverUrlKey = 'server_url';
  static const _inviteCodeKey = 'invite_code';
  static const _askedNotificationPermissionKey =
      'asked_notification_permission';
  static const _windowBoundsKey = 'window_bounds';
  static const _windowMaximizedKey = 'window_maximized';
  static const _windowAlwaysOnTopKey = 'window_always_on_top';
  static const _miniWindowPositionKey = 'mini_window_position';
  static const _shareFocusedAppKey = 'share_focused_app';
  static const _shareUnknownAppsKey = 'share_unknown_apps';
  static const _shareLocationKey = 'share_location';
  static const _collapsedHomeSectionsKey = 'collapsed_home_sections';
  static const _autostartEnabledKey = 'autostart_enabled';
  static const _shareVitalsKey = 'share_vitals';
  static const _notificationSoundKeyPrefix = 'notification_sound_';

  final SharedPreferences _prefs;

  static Future<PrefsService> create() async {
    return PrefsService(await SharedPreferences.getInstance());
  }

  String? get serverUrl => _prefs.getString(_serverUrlKey);

  Future<void> setServerUrl(String url) => _prefs.setString(_serverUrlKey, url);

  Future<void> clearServerUrl() => _prefs.remove(_serverUrlKey);

  /// The `couples.invite_code` field is server-side hidden, so it's only
  /// ever handed to the client once, in the POST /api/couple/create
  /// response. We stash it locally so the waiting-for-partner empty state
  /// can keep showing it after an app restart.
  String? get inviteCode => _prefs.getString(_inviteCodeKey);

  Future<void> setInviteCode(String code) =>
      _prefs.setString(_inviteCodeKey, code);

  /// Android's POST_NOTIFICATIONS prompt is a one-shot: deny it twice and
  /// the system stops showing it forever. So we ask exactly once, on the
  /// first run that gets as far as the home screen, and after that the
  /// only route is the "phone superpowers" screen — where the user is the
  /// one initiating.
  bool get askedNotificationPermission =>
      _prefs.getBool(_askedNotificationPermissionKey) ?? false;

  Future<void> markAskedNotificationPermission() =>
      _prefs.setBool(_askedNotificationPermissionKey, true);

  /// Desktop only (see [DesktopWindowService]): where the user left the
  /// companion window last time, stored as "x,y,width,height". Null on first
  /// run — and on anything unparseable, so a corrupted value just means
  /// "dock me bottom-right again" rather than a crash on launch.
  Rect? get windowBounds {
    final raw = _prefs.getString(_windowBoundsKey);
    if (raw == null) return null;
    final parts = raw.split(',').map(double.tryParse).toList();
    if (parts.length != 4 || parts.any((v) => v == null)) return null;
    return Rect.fromLTWH(parts[0]!, parts[1]!, parts[2]!, parts[3]!);
  }

  Future<void> setWindowBounds(Rect bounds) => _prefs.setString(
    _windowBoundsKey,
    '${bounds.left},${bounds.top},${bounds.width},${bounds.height}',
  );

  /// Kept separately from [windowBounds] so a maximized window restores as
  /// maximized without overwriting the pane size the user picked.
  bool get windowMaximized => _prefs.getBool(_windowMaximizedKey) ?? false;

  Future<void> setWindowMaximized(bool value) =>
      _prefs.setBool(_windowMaximizedKey, value);

  /// Where the little always-there card was last left, kept apart from
  /// [windowBounds] so the card and the panel each stay where they were put.
  /// Size isn't stored — the card is a fixed 240×150.
  Offset? get miniWindowPosition {
    final raw = _prefs.getString(_miniWindowPositionKey);
    if (raw == null) return null;
    final parts = raw.split(',').map(double.tryParse).toList();
    if (parts.length != 2 || parts.any((v) => v == null || !v.isFinite)) {
      return null;
    }
    return Offset(parts[0]!, parts[1]!);
  }

  Future<void> setMiniWindowPosition(Offset position) =>
      _prefs.setString(_miniWindowPositionKey, '${position.dx},${position.dy}');

  bool get windowAlwaysOnTop => _prefs.getBool(_windowAlwaysOnTopKey) ?? false;

  Future<void> setWindowAlwaysOnTop(bool value) =>
      _prefs.setBool(_windowAlwaysOnTopKey, value);

  /// Per-device opt-in for the "focused-app status" feature
  /// (kb/features.md): share a friendly-mapped label of whichever app has
  /// focus (Windows) or is in the foreground (Android). Off by default —
  /// this is the one that reads the most like activity tracking, so it
  /// never turns itself on.
  bool get shareFocusedApp => _prefs.getBool(_shareFocusedAppKey) ?? false;

  Future<void> setShareFocusedApp(bool value) =>
      _prefs.setBool(_shareFocusedAppKey, value);

  /// Whether an app with no entry in `ActivityMapper`'s table still gets a
  /// cleaned-up guess instead of staying silent. Meaningless — and never
  /// consulted — while [shareFocusedApp] itself is off.
  bool get shareUnknownApps => _prefs.getBool(_shareUnknownAppsKey) ?? false;

  Future<void> setShareUnknownApps(bool value) =>
      _prefs.setBool(_shareUnknownAppsKey, value);

  /// Whether the app itself should act as its own OwnTracks-compatible
  /// tracker (kb/contracts.md "Location": "The app itself MAY also post its
  /// own location later via the same route with the same auth") — this is
  /// that "later". Off by default, same as every other sharing opt-in: a
  /// couples app never starts reporting a dot on the map without being
  /// asked. OwnTracks itself remains a fully supported alternative; turning
  /// this on doesn't require turning that off, and vice versa.
  bool get shareLocation => _prefs.getBool(_shareLocationKey) ?? false;

  Future<void> setShareLocation(bool value) =>
      _prefs.setBool(_shareLocationKey, value);

  /// Which phone-column home sections are collapsed, stored by name (the
  /// section's enum `.name`, e.g. "countdowns"). Null means "never saved" —
  /// the caller applies its own first-run defaults rather than us baking
  /// UI-layer defaults into this data-layer service. An empty (non-null)
  /// list is a legitimate saved state: everything expanded. Unknown names
  /// (an older/newer build's section that this build doesn't recognise) are
  /// simply ignored by the reader, never dropped from what we write back.
  List<String>? get collapsedHomeSections =>
      _prefs.getStringList(_collapsedHomeSectionsKey);

  Future<void> setCollapsedHomeSections(List<String> sectionNames) =>
      _prefs.setStringList(_collapsedHomeSectionsKey, sectionNames);

  /// Re-reads the backing store from disk. SharedPreferences caches values
  /// per isolate, so the background isolate MUST call this before re-reading
  /// settings the UI isolate may have changed — without it, a toggle flipped
  /// in the app never reaches the foreground service (this exact bug shipped
  /// once: shareLocation stayed stale-false in the service forever).
  Future<void> reload() => _prefs.reload();

  /// Desktop only (see [AutostartService]): whether "start with the
  /// computer" is turned on, from the tray menu's checkbox. This is what
  /// the checkbox itself renders as checked — the source of truth for the
  /// UI — separate from whatever the OS actually has registered right now,
  /// which [AutostartService.isEnabledOnSystem] checks fresh. Off by
  /// default, like every other opt-in in this app.
  bool get autostartEnabled => _prefs.getBool(_autostartEnabledKey) ?? false;

  Future<void> setAutostartEnabled(bool value) =>
      _prefs.setBool(_autostartEnabledKey, value);

  /// Phone-only opt-in for the smartwatch-vitals feature (kb/features.md):
  /// share today's steps and the latest heart-rate sample from Health
  /// Connect with the partner. Off by default like every other sharing
  /// toggle — a heartbeat is intimate data and never starts broadcasting
  /// itself. Read by the background isolate (which does the actual Health
  /// Connect reads), so changes must be pushed via sendDataToTask AND
  /// survive the reload() dance like the other sharing prefs.
  bool get shareVitals => _prefs.getBool(_shareVitalsKey) ?? false;

  Future<void> setShareVitals(bool value) =>
      _prefs.setBool(_shareVitalsKey, value);

  /// Which bundled sound plays for one notification event type
  /// (kb/features.md "Custom notification sounds"). [eventId] is a
  /// `KehaiEventKind.id` ("ping", "doodle", "instant", "reveal") and the
  /// value is a `KehaiSound.id`.
  ///
  /// Stored as one key per event rather than a map/JSON blob: it's four
  /// scalar strings that are read individually and written individually, and
  /// a blob would only add a parse step that can fail. Null means "never
  /// chosen" — the caller substitutes the event's own default
  /// (`KehaiEventKind.defaultSound`) rather than this layer knowing about
  /// them, same reasoning as [collapsedHomeSections].
  String? notificationSound(String eventId) =>
      _prefs.getString('$_notificationSoundKeyPrefix$eventId');

  Future<void> setNotificationSound(String eventId, String soundId) =>
      _prefs.setString('$_notificationSoundKeyPrefix$eventId', soundId);
}

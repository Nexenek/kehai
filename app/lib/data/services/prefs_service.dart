import 'dart:ui' show Rect;

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

  bool get windowAlwaysOnTop => _prefs.getBool(_windowAlwaysOnTopKey) ?? false;

  Future<void> setWindowAlwaysOnTop(bool value) =>
      _prefs.setBool(_windowAlwaysOnTopKey, value);
}

import 'package:shared_preferences/shared_preferences.dart';

/// Thin wrapper around [SharedPreferences] for the handful of values we
/// persist outside the PocketBase auth store: the server URL and the last
/// invite-code the user was shown.
class PrefsService {
  PrefsService(this._prefs);

  static const _serverUrlKey = 'server_url';
  static const _inviteCodeKey = 'invite_code';
  static const _askedNotificationPermissionKey = 'asked_notification_permission';

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
}

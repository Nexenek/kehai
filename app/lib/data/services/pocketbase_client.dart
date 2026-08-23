import 'package:pocketbase/pocketbase.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Builds the single [PocketBase] client instance the app shares, wiring
/// its [AuthStore] up to [SharedPreferences] so a session survives an app
/// restart (per spec: shared_preferences for "server URL + session
/// persistence").
class PocketBaseClientFactory {
  const PocketBaseClientFactory._();

  static const _authKey = 'pb_auth';

  static Future<PocketBase> create(String baseUrl) async {
    final prefs = await SharedPreferences.getInstance();
    final store = AsyncAuthStore(
      save: (String data) async => prefs.setString(_authKey, data),
      initial: prefs.getString(_authKey),
      clear: () async => prefs.remove(_authKey),
    );
    return PocketBase(baseUrl, authStore: store);
  }
}

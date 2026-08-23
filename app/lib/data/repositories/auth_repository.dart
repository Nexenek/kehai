import 'package:pocketbase/pocketbase.dart';

/// Wraps PocketBase's standard `users` auth collection: register, login,
/// logout, and the currently-authenticated record.
class AuthRepository {
  AuthRepository(this._pb);

  final PocketBase _pb;

  bool get isLoggedIn => _pb.authStore.isValid;

  RecordModel? get currentUser => _pb.authStore.record;

  String get currentUserId => _pb.authStore.record?.id ?? '';

  String? get coupleId {
    final couple = currentUser?.get<String>('couple');
    return (couple == null || couple.isEmpty) ? null : couple;
  }

  Stream<AuthStoreEvent> get onChange => _pb.authStore.onChange;

  Future<void> register({
    required String email,
    required String password,
    required String name,
  }) async {
    await _pb
        .collection('users')
        .create(
          body: {
            'email': email,
            'password': password,
            'passwordConfirm': password,
            'name': name,
          },
        );
    await login(email: email, password: password);
  }

  Future<void> login({required String email, required String password}) async {
    await _pb.collection('users').authWithPassword(email, password);
  }

  void logout() {
    _pb.authStore.clear();
  }

  /// Re-fetches the auth record from the server — needed after the couple
  /// custom routes mutate the user's `couple` field server-side, since the
  /// local auth store otherwise stays stale.
  Future<void> refresh() async {
    if (!isLoggedIn) return;
    await _pb.collection('users').authRefresh();
  }
}

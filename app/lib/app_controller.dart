import 'package:flutter/widgets.dart';

import 'data/repositories/auth_repository.dart';
import 'data/repositories/couple_repository.dart';
import 'data/repositories/device_repository.dart';
import 'data/repositories/status_repository.dart';
import 'data/services/device_info_service.dart';
import 'data/services/heartbeat_service.dart';
import 'data/services/pocketbase_client.dart';
import 'data/services/prefs_service.dart';

/// Which screen the app should currently show. This is intentionally a
/// flat state machine rather than a router — the onboarding flow is
/// strictly linear and the whole app is one couple's home, so named routes
/// would add ceremony without buying anything.
enum AppStage { loading, serverSetup, auth, coupleSetup, home }

/// The composition root: owns the PocketBase client and every
/// repository/service built on top of it, and tracks which [AppStage] the
/// app is in. Plain [ChangeNotifier] per the "avoid heavyweight state
/// management" instruction — screens listen via [AppScope]/ListenableBuilder.
class AppController extends ChangeNotifier {
  AppController();

  late final PrefsService prefs;
  final DeviceInfoService deviceInfoService = const DeviceInfoService();

  AppStage stage = AppStage.loading;
  String? connectionError;

  AuthRepository? authRepository;
  CoupleRepository? coupleRepository;
  StatusRepository? statusRepository;
  DeviceRepository? deviceRepository;
  HeartbeatService? heartbeatService;

  String get serverUrl => prefs.serverUrl ?? '';

  Future<void> init() async {
    prefs = await PrefsService.create();
    final savedUrl = prefs.serverUrl;
    if (savedUrl == null || savedUrl.isEmpty) {
      stage = AppStage.serverSetup;
      notifyListeners();
      return;
    }

    final ok = await _connect(savedUrl);
    if (!ok) {
      stage = AppStage.serverSetup;
      notifyListeners();
      return;
    }
    _resolveStageAfterConnect();
    notifyListeners();
  }

  /// Tries to reach [url]'s health endpoint without persisting anything —
  /// used by the "test connection" button.
  Future<bool> testConnection(String url) async {
    try {
      final pb = await PocketBaseClientFactory.create(_normalize(url));
      await pb.health.check();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Confirms [url] works, persists it, and moves on to auth/couple/home.
  Future<bool> confirmServer(String url) async {
    final normalized = _normalize(url);
    final ok = await _connect(normalized);
    if (!ok) {
      notifyListeners();
      return false;
    }
    await prefs.setServerUrl(normalized);
    _resolveStageAfterConnect();
    notifyListeners();
    return true;
  }

  Future<bool> _connect(String url) async {
    try {
      final pb = await PocketBaseClientFactory.create(url);
      await pb.health.check();
      authRepository = AuthRepository(pb);
      coupleRepository = CoupleRepository(pb, authRepository!);
      statusRepository = StatusRepository(pb);
      deviceRepository = DeviceRepository(pb);
      heartbeatService = HeartbeatService(deviceRepository!, deviceInfoService);
      connectionError = null;
      return true;
    } catch (_) {
      connectionError = "couldn't reach your server (・_・;) — check the address or Tailscale?";
      return false;
    }
  }

  void _resolveStageAfterConnect() {
    final auth = authRepository!;
    if (!auth.isLoggedIn) {
      stage = AppStage.auth;
      return;
    }
    stage = auth.coupleId == null ? AppStage.coupleSetup : AppStage.home;
  }

  /// Called after a successful login/register.
  void onAuthenticated() {
    final coupleId = authRepository?.coupleId;
    stage = coupleId == null ? AppStage.coupleSetup : AppStage.home;
    notifyListeners();
  }

  /// Called after creating/joining a couple.
  void onCoupleReady() {
    stage = AppStage.home;
    notifyListeners();
  }

  void logOut() {
    heartbeatService?.stop();
    authRepository?.logout();
    stage = AppStage.auth;
    notifyListeners();
  }

  String _normalize(String url) {
    var u = url.trim();
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    return u;
  }
}

/// Makes the [AppController] reachable from any widget below it via
/// `AppScope.of(context)`.
class AppScope extends InheritedNotifier<AppController> {
  const AppScope({super.key, required AppController controller, required super.child})
      : super(notifier: controller);

  static AppController of(BuildContext context, {bool listen = true}) {
    final scope = listen
        ? context.dependOnInheritedWidgetOfExactType<AppScope>()
        : context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope.of() called with no AppScope ancestor');
    return scope!.notifier!;
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import 'updates/update_installer.dart';
import 'updates/update_release.dart';

/// Where an update currently stands. Straight out of the design doc:
/// `idle → checking → available → downloading → readyToApply → applying`,
/// with [failed] reachable from any of the active ones.
///
/// [idle] doubles as "nothing to report" — up to date, never checked, or a
/// quiet background check that found nothing are all the same thing to the
/// one line of UI this drives.
enum UpdateStage {
  idle,
  checking,
  available,
  downloading,
  readyToApply,
  applying,
  failed,
}

/// Which step a [UpdateStage.failed] failed at, so retry re-runs *that*
/// step rather than starting from the top.
enum UpdateStep { check, download, apply }

/// A debug-only way to make the running app pretend it is older than it is,
/// so a real "newer" release can be exercised end to end without publishing
/// one:
///
/// ```
/// flutter run --dart-define=KEHAI_FAKE_VERSION=0.9.0
/// ```
///
/// This is also the *only* thing that turns updates on outside a release
/// build. The rule is deliberately not a plain `kReleaseMode` guard: a
/// debug build must never swap itself (its APK is signed with the debug
/// key, and its desktop bundle isn't the one the archive contains), but a
/// blanket guard would also make the feature impossible to test by hand
/// before shipping it. So: release builds always, debug builds only when
/// somebody explicitly asked for it by setting this define.
const kehaiFakeVersion = String.fromEnvironment('KEHAI_FAKE_VERSION');

/// "Is there a newer Kehai, and would you like it?" — the whole of the
/// auto-update feature's state, as a plain [ChangeNotifier] (house style;
/// same shape as every view model here).
///
/// Everything with a side effect is injected: the HTTP fetch, the platform
/// [UpdateInstaller], and the current-version supplier. What's left in this
/// class is scheduling and a state machine, which is what
/// update_service_test.dart drives with `fakeAsync` and no network.
class UpdateService extends ChangeNotifier {
  UpdateService({
    required UpdateInstaller? installer,
    Future<String> Function()? currentVersion,
    Future<String> Function(Uri url)? fetch,
    bool? enabled,
    this.checkInterval = const Duration(hours: 24),
    this.retryInterval = const Duration(hours: 1),
  }) : _installer = installer,
       _currentVersion = currentVersion ?? _platformVersion,
       _fetch = fetch ?? _httpGet,
       _enabled = (enabled ?? updatesEnabled) && installer != null;

  /// Where the app looks. Unauthenticated; the endpoint already excludes
  /// drafts and prereleases, which is the entire release-side contract.
  static final Uri latestReleaseUrl = Uri.parse(
    'https://api.github.com/repos/Nexenek/kehai/releases/latest',
  );

  /// Whether this build is allowed to update itself at all — see
  /// [kehaiFakeVersion] for why it isn't simply [kReleaseMode].
  static bool get updatesEnabled => kReleaseMode || kehaiFakeVersion.isNotEmpty;

  /// The happy cadence: one check a day while the app is running.
  final Duration checkInterval;

  /// The unhappy one. A background check that failed (no tailnet, GitHub
  /// having a moment) shouldn't wait a full day to try again, and shouldn't
  /// say anything either.
  final Duration retryInterval;

  final UpdateInstaller? _installer;
  final Future<String> Function() _currentVersion;
  final Future<String> Function(Uri url) _fetch;
  final bool _enabled;

  UpdateStage _stage = UpdateStage.idle;
  String? _availableVersion;
  String? _releaseNotes;
  ReleaseAsset? _asset;
  UpdateStaging? _staging;
  double _progress = 0;
  String? _failureReason;
  UpdateStep? _failedStep;
  String? _lastCheckError;

  bool _running = false;
  bool _firstCheckStarted = false;
  Timer? _timer;

  /// True when this build can update itself. False in an ordinary debug run
  /// (and on any platform we don't ship a self-updating build for), where
  /// every method below is a no-op and the chip never appears.
  bool get isEnabled => _enabled;

  UpdateStage get stage => _stage;

  /// The version being offered, downloaded, or installed — null whenever
  /// there is nothing to offer.
  String? get availableVersion => _availableVersion;

  /// The release body. Nothing renders it yet; it's parsed anyway because
  /// it arrives in the same response.
  String? get releaseNotes => _releaseNotes;

  /// 0..1 while [UpdateStage.downloading], meaningless otherwise.
  double get progress => _progress;

  String? get failureReason => _failureReason;

  UpdateStep? get failedStep => _failedStep;

  /// Why the last check didn't answer, if it didn't. Kept separately from
  /// [failureReason] because a background check that fails is *not* an
  /// error the user is shown — it's a log line and a shorter retry.
  String? get lastCheckError => _lastCheckError;

  /// Whether there's an update the user could start right now.
  bool get hasUpdate => _stage == UpdateStage.available;

  /// Whether an update is mid-flight, i.e. a periodic check must stay out
  /// of the way.
  bool get isBusy =>
      _stage == UpdateStage.downloading ||
      _stage == UpdateStage.readyToApply ||
      _stage == UpdateStage.applying;

  /// Begins the update loop, but does *not* check yet: the first check
  /// waits for [reportOnline]. Kehai autostarts at login and its server is
  /// a home machine on a tailnet, so the first seconds of a session are
  /// routinely offline — checking then would spend the launch check on a
  /// failure and then sit quiet for a day.
  ///
  /// Also the moment the last update's leftovers go (Linux's `<dir>.old`,
  /// Android's spent APK): we are running, so whatever we installed works.
  void start() {
    if (!_enabled || _running) return;
    _running = true;
    unawaited(_installer!.cleanUpAfterUpdate());
  }

  /// "The server answered" — from [ConnectivityMonitor]'s probe. The first
  /// one releases the launch check; the rest are no-ops, since the 24 h
  /// timer takes over from there.
  void reportOnline() {
    if (!_enabled || !_running || _firstCheckStarted) return;
    _firstCheckStarted = true;
    unawaited(checkNow());
  }

  /// Asks GitHub what the latest release is.
  ///
  /// [manual] is the tray/settings entry: it's the only caller allowed to
  /// turn a failure into something the user sees, because it's the only
  /// caller somebody is waiting on.
  Future<void> checkNow({bool manual = false}) async {
    if (!_enabled) return;
    // One thing at a time. A download in flight owns the state machine, and
    // a second check while one is already out is just noise.
    if (_stage == UpdateStage.checking || isBusy) return;
    _firstCheckStarted = true;

    final previousStage = _stage;
    _stage = UpdateStage.checking;
    notifyListeners();

    try {
      final body = await _fetch(latestReleaseUrl);
      final release = parseLatestRelease(body);
      if (release == null) throw StateError('unreadable release');
      final current = await _currentVersion();
      final asset = selectAsset(release.assets, _installer!.target);

      _lastCheckError = null;
      if (asset != null && isNewerVersion(release.version, current)) {
        _asset = asset;
        _availableVersion = release.version;
        _releaseNotes = release.notes;
        _stage = UpdateStage.available;
      } else {
        _asset = null;
        _availableVersion = null;
        _releaseNotes = null;
        _stage = UpdateStage.idle;
      }
      _failureReason = null;
      _failedStep = null;
      _schedule(checkInterval);
    } catch (error) {
      _lastCheckError = '$error';
      debugPrint('update check failed: $error');
      if (manual) {
        _fail(UpdateStep.check, error);
      } else {
        // Quietly back to wherever we were — an offer already on screen
        // must not be replaced by an error nobody asked for.
        _stage = previousStage == UpdateStage.checking
            ? UpdateStage.idle
            : previousStage;
      }
      _schedule(retryInterval);
    }
    notifyListeners();
  }

  /// The chip's tap, and the tray's "update to vX.Y.Z": download the asset,
  /// verify it, put it in place. On desktop the last step ends the process.
  Future<void> startUpdate() async {
    if (!_enabled || isBusy) return;
    final asset = _asset;
    if (asset == null) return;

    _stage = UpdateStage.downloading;
    _progress = 0;
    _failureReason = null;
    _failedStep = null;
    notifyListeners();

    UpdateStaging? staging;
    try {
      staging = await _installer!.stage(
        asset,
        onProgress: (value) {
          // Only worth a repaint when the rounded percentage actually
          // moves — the chip renders whole percent.
          if ((value * 100).floor() == (_progress * 100).floor()) return;
          _progress = value;
          notifyListeners();
        },
      );
      _staging = staging;
      _progress = 1;
      _stage = UpdateStage.readyToApply;
      notifyListeners();
    } catch (error) {
      _fail(UpdateStep.download, error);
      notifyListeners();
      return;
    }

    _stage = UpdateStage.applying;
    notifyListeners();
    try {
      await _installer.apply(staging);
    } catch (error) {
      _fail(UpdateStep.apply, error);
      notifyListeners();
    }
  }

  /// Re-runs whatever failed — never the whole sequence. A download that
  /// died at 90% retries the download; a check that couldn't reach GitHub
  /// retries the check.
  Future<void> retry() async {
    if (!_enabled || _stage != UpdateStage.failed) return;
    switch (_failedStep) {
      case UpdateStep.check:
      case null:
        await checkNow(manual: true);
      case UpdateStep.download:
      case UpdateStep.apply:
        await startUpdate();
    }
  }

  /// What one tap on the chip means, given where we are: start it, or try
  /// again. Anything else is not tappable.
  Future<void> onTap() async {
    switch (_stage) {
      case UpdateStage.available:
        await startUpdate();
      case UpdateStage.failed:
        await retry();
      case _:
        break;
    }
  }

  void _fail(UpdateStep step, Object error) {
    debugPrint('update ${step.name} failed: $error');
    _failedStep = step;
    _failureReason = '$error';
    _stage = UpdateStage.failed;
    // A half-downloaded staging dir is dead weight; the retry makes a fresh
    // one. (Not on an apply failure — that staging is still good.)
    if (step == UpdateStep.download && _staging != null) {
      unawaited(_installer!.discard(_staging!));
      _staging = null;
    }
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    if (!_running) return;
    _timer = Timer(delay, () => unawaited(checkNow()));
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }

  static Future<String> _platformVersion() async {
    if (kehaiFakeVersion.isNotEmpty) return kehaiFakeVersion;
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  static Future<String> _httpGet(Uri url) async {
    final response = await http.get(
      url,
      headers: const {
        // GitHub refuses unauthenticated API requests without one.
        'User-Agent': updateUserAgent,
        'Accept': 'application/vnd.github+json',
      },
    );
    if (response.statusCode != 200) {
      throw HttpExceptionLite(response.statusCode, url);
    }
    return response.body;
  }
}

/// A tiny stand-in for `dart:io`'s `HttpException` so this file stays
/// importable from anywhere (and so the message reads like something a
/// person wrote).
class HttpExceptionLite implements Exception {
  const HttpExceptionLite(this.statusCode, this.url);

  final int statusCode;
  final Uri url;

  @override
  String toString() => 'github said $statusCode';
}

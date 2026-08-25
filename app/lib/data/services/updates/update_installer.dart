import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../desktop_window_service.dart';
import 'update_release.dart';
import 'update_scripts.dart';

/// A verified copy of the new version, sitting somewhere harmless.
///
/// The running installation is never touched until one of these exists —
/// that's the whole failure story (spec: "every failure lands in
/// `failed(reason)` with the old version still running").
class UpdateStaging {
  const UpdateStaging({required this.payloadPath, required this.scratchDir});

  /// What gets installed: the downloaded `.apk` on Android, the extracted
  /// bundle directory on desktop.
  final String payloadPath;

  /// The temp directory holding [payloadPath] (and the archive it came out
  /// of), so a failed or abandoned update can be swept up in one call.
  final String scratchDir;
}

/// The platform half of an update: fetch it somewhere safe, then put it in
/// place. [UpdateService] owns the state machine around these two steps and
/// knows nothing about zips, `mv`, or Android intents.
abstract interface class UpdateInstaller {
  /// Which release asset this platform installs.
  UpdateTarget get target;

  /// Downloads [asset], verifies it, and (on desktop) unpacks it. Throws on
  /// anything that would leave us with a half-update.
  Future<UpdateStaging> stage(
    ReleaseAsset asset, {
    void Function(double progress)? onProgress,
  });

  /// Puts a staged update in place. On desktop this ends the process — the
  /// call is not expected to return.
  Future<void> apply(UpdateStaging staging);

  /// Called once on every healthy start: throws away whatever the last
  /// update left behind.
  Future<void> cleanUpAfterUpdate();

  /// Best-effort removal of an abandoned staging dir.
  Future<void> discard(UpdateStaging staging);
}

/// Builds the installer for the platform we're actually on, or null where
/// Kehai isn't shipped as a self-updating build (macOS, iOS, web) — the
/// service treats that exactly like "updates disabled".
UpdateInstaller? createUpdateInstaller() {
  if (Platform.isAndroid) return AndroidUpdateInstaller();
  if (Platform.isWindows || Platform.isLinux) {
    return DesktopUpdateInstaller(
      // The single exit the whole app has (see [WindowModeController.quit]):
      // tray teardown, window bounds persisted, then `destroy()`. The helper
      // script is already spawned and waiting on our PID by the time this
      // runs.
      quit: () => DesktopWindowService.instance.windowMode.quit(),
    );
  }
  return null;
}

/// Streams [asset] into [destination], reporting progress, and refuses
/// anything whose length doesn't match what the API promised.
///
/// Shared by both installers because the download is the one step that is
/// genuinely identical everywhere — the size check included, which is the
/// only integrity check we do (spec's "Failure handling").
Future<void> downloadAsset(
  ReleaseAsset asset,
  File destination, {
  void Function(double progress)? onProgress,
  http.Client? client,
}) async {
  final owned = client == null;
  final httpClient = client ?? http.Client();
  IOSink? sink;
  try {
    final request = http.Request('GET', Uri.parse(asset.downloadUrl))
      ..headers['User-Agent'] = updateUserAgent;
    final response = await httpClient.send(request);
    if (response.statusCode != 200) {
      throw HttpException(
        'download failed (${response.statusCode})',
        uri: Uri.parse(asset.downloadUrl),
      );
    }
    final total = response.contentLength ?? asset.size;
    var received = 0;
    sink = destination.openWrite();
    await for (final chunk in response.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) onProgress?.call((received / total).clamp(0.0, 1.0));
    }
    await sink.flush();
    await sink.close();
    sink = null;

    final written = await destination.length();
    // A truncated download is the common corruption here (a tailnet that
    // dropped mid-transfer), and it is exactly what the advertised size
    // catches. Size 0 means the API didn't tell us — take what we got.
    if (asset.size > 0 && written != asset.size) {
      throw StateError('size mismatch: got $written, expected ${asset.size}');
    }
  } finally {
    await sink?.close();
    if (owned) httpClient.close();
  }
}

/// GitHub rejects unauthenticated API calls without one.
const updateUserAgent = 'Kehai-Updater';

/// Android: download to the app's cache dir, hand the file to the system
/// installer, and let the OS do the rest.
///
/// Both halves go through one small MethodChannel in `MainActivity` (see
/// `android/app/src/main/kotlin/app/kehai/MainActivity.kt`) rather than a
/// plugin: `cacheDir` because that's the directory `file_paths.xml` scopes
/// the FileProvider to, and `installApk` because firing `ACTION_VIEW` with a
/// `content://` URI needs an Activity.
class AndroidUpdateInstaller implements UpdateInstaller {
  AndroidUpdateInstaller({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'kehai/updates';

  final MethodChannel _channel;

  @override
  UpdateTarget get target => UpdateTarget.android;

  @override
  Future<UpdateStaging> stage(
    ReleaseAsset asset, {
    void Function(double progress)? onProgress,
  }) async {
    final cacheDir = await _channel.invokeMethod<String>('cacheDir');
    if (cacheDir == null || cacheDir.isEmpty) {
      throw StateError('no cache directory');
    }
    final dir = Directory('$cacheDir${Platform.pathSeparator}updates');
    // One update at a time, and never two APKs on disk: the whole directory
    // is disposable and the installer is done with the file the moment the
    // user confirms.
    if (dir.existsSync()) await dir.delete(recursive: true);
    await dir.create(recursive: true);

    final apk = File('${dir.path}${Platform.pathSeparator}${asset.name}');
    await downloadAsset(asset, apk, onProgress: onProgress);
    return UpdateStaging(payloadPath: apk.path, scratchDir: dir.path);
  }

  @override
  Future<void> apply(UpdateStaging staging) async {
    // Hands over to the system installer's confirm sheet. Kehai keeps
    // running behind it — the OS replaces us in place (same keystore), so
    // there is nothing for us to quit or clean up.
    await _channel.invokeMethod<void>('installApk', staging.payloadPath);
  }

  @override
  Future<void> cleanUpAfterUpdate() async {
    // The APK we installed from is dead weight the moment the install is
    // confirmed, and the cache dir is the OS's to reclaim anyway — but a
    // 60 MB file we know is spent may as well go now.
    try {
      final cacheDir = await _channel.invokeMethod<String>('cacheDir');
      if (cacheDir == null || cacheDir.isEmpty) return;
      final dir = Directory('$cacheDir${Platform.pathSeparator}updates');
      if (dir.existsSync()) await dir.delete(recursive: true);
    } catch (error) {
      debugPrint('update cleanup skipped: $error');
    }
  }

  @override
  Future<void> discard(UpdateStaging staging) => _deleteQuietly(staging);
}

/// Windows and Linux: download the archive, unpack it beside itself, prove
/// the executable is in there, then let a detached helper script do the
/// swap while we're on our way out.
///
/// The target is always the *running* bundle's own directory
/// ([Platform.resolvedExecutable]'s parent), so this works whether the app
/// was installed by `install.sh` into `~/.local/opt/kehai`, unzipped onto a
/// desktop, or run from a build output — and desktop-entry `Exec=` paths
/// stay valid, because the directory itself never moves.
class DesktopUpdateInstaller implements UpdateInstaller {
  DesktopUpdateInstaller({
    required Future<void> Function() quit,
    String? executablePath,
    Future<ProcessResult> Function(String, List<String>)? run,
    Future<void> Function(String script, String workingDir)? spawnHelper,
  }) : _quit = quit,
       _executablePath = executablePath ?? Platform.resolvedExecutable,
       _run = run ?? Process.run,
       _spawnHelper = spawnHelper;

  final Future<void> Function() _quit;
  final String _executablePath;
  final Future<ProcessResult> Function(String, List<String>) _run;
  final Future<void> Function(String script, String workingDir)? _spawnHelper;

  @override
  UpdateTarget get target =>
      Platform.isWindows ? UpdateTarget.windows : UpdateTarget.linux;

  /// The directory that gets replaced.
  String get installDir => _parentOf(_executablePath);

  /// e.g. `couples_app.exe` / `couples_app` — read off the running binary
  /// rather than hardcoded, so a rename of the Flutter target doesn't
  /// silently break the "did the archive actually contain the app?" check.
  String get executableName => _basename(_executablePath);

  @override
  Future<UpdateStaging> stage(
    ReleaseAsset asset, {
    void Function(double progress)? onProgress,
  }) async {
    final scratch = await Directory.systemTemp.createTemp('kehai_update_');
    try {
      final archive = File(
        '${scratch.path}${Platform.pathSeparator}${asset.name}',
      );
      await downloadAsset(asset, archive, onProgress: onProgress);

      final extracted = Directory(
        '${scratch.path}${Platform.pathSeparator}extracted',
      );
      await extracted.create(recursive: true);
      await _extract(archive, extracted);

      final payload = _findBundle(extracted);
      if (payload == null) {
        throw StateError('$executableName not found in ${asset.name}');
      }
      return UpdateStaging(payloadPath: payload, scratchDir: scratch.path);
    } catch (_) {
      await _deleteDir(scratch.path);
      rethrow;
    }
  }

  /// PowerShell on Windows, `tar` on Linux — both already on the box, so
  /// unpacking costs no new Dart dependency. A non-zero exit is treated as
  /// corruption, which is the other half of the integrity story the size
  /// check starts.
  Future<void> _extract(File archive, Directory into) async {
    final ProcessResult result;
    if (Platform.isWindows) {
      result = await _run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        "Expand-Archive -LiteralPath '${archive.path}' "
            "-DestinationPath '${into.path}' -Force",
      ]);
    } else {
      result = await _run('tar', ['-xzf', archive.path, '-C', into.path]);
    }
    if (result.exitCode != 0) {
      throw StateError('could not unpack ${_basename(archive.path)}');
    }
  }

  /// Finds the directory holding [executableName] inside a freshly
  /// extracted archive.
  ///
  /// Two layouts to cover, both of which we ship today: the Windows zip is
  /// flat (`couples_app.exe` at the root) and the Linux tarball nests
  /// (`kehai-linux-x64-1.0.3/bundle/couples_app`). Two levels down is
  /// therefore enough, and bounding it keeps a hostile or weird archive from
  /// turning this into a filesystem walk.
  String? _findBundle(Directory root) {
    for (final dir in _candidateDirs(root)) {
      final exe = File('${dir.path}${Platform.pathSeparator}$executableName');
      if (exe.existsSync()) return dir.path;
    }
    return null;
  }

  Iterable<Directory> _candidateDirs(Directory root) sync* {
    yield root;
    for (final child in root.listSync().whereType<Directory>()) {
      yield child;
      yield* child.listSync().whereType<Directory>();
    }
  }

  @override
  Future<void> apply(UpdateStaging staging) async {
    final script = Platform.isWindows
        ? windowsUpdateScript(
            pid: pid,
            stagingDir: staging.payloadPath,
            installDir: installDir,
            exePath: _executablePath,
          )
        : linuxUpdateScript(
            pid: pid,
            stagingDir: staging.payloadPath,
            installDir: installDir,
            exePath: _executablePath,
          );

    // Beside the staging dir, not inside it: on Linux the staging dir is
    // renamed *into place*, and a helper script that came along for the ride
    // would end up installed as part of the app.
    final helper = File(
      '${staging.scratchDir}${Platform.pathSeparator}'
      'kehai_update${Platform.isWindows ? '.bat' : '.sh'}',
    );
    await helper.writeAsString(script);
    if (!Platform.isWindows) {
      await _run('chmod', ['+x', helper.path]);
    }

    final spawn = _spawnHelper ?? _spawnDetached;
    await spawn(helper.path, staging.scratchDir);
    // From here the helper is watching our PID. Quitting *is* the rest of
    // the update.
    await _quit();
  }

  Future<void> _spawnDetached(String script, String workingDir) async {
    if (Platform.isWindows) {
      await Process.start(
        'cmd',
        ['/c', 'start', '', '/min', script],
        workingDirectory: workingDir,
        mode: ProcessStartMode.detached,
      );
    } else {
      await Process.start(
        '/usr/bin/env',
        ['bash', script],
        workingDirectory: '/',
        mode: ProcessStartMode.detached,
      );
    }
  }

  @override
  Future<void> cleanUpAfterUpdate() async {
    // The helper script can't remove its own scratch dir (on Windows a batch
    // file is read from disk as it runs, so deleting the directory over its
    // own head is not an option), so each update leaves one `kehai_update_*`
    // temp dir holding the spent archive. Swept here instead: at startup no
    // update is in flight, so anything matching the prefix is a leftover.
    try {
      for (final entry in Directory.systemTemp.listSync()) {
        if (entry is Directory &&
            _basename(entry.path).startsWith('kehai_update_')) {
          await _deleteDir(entry.path);
        }
      }
    } catch (error) {
      debugPrint('update scratch sweep skipped: $error');
    }
    // Linux's safety copy from the last update. It survives exactly one
    // cycle: if we got far enough to run again, the new version starts, so
    // the old one has done its job.
    if (Platform.isWindows) return;
    await _deleteDir(backupDirPath(installDir));
  }

  @override
  Future<void> discard(UpdateStaging staging) => _deleteQuietly(staging);
}

Future<void> _deleteQuietly(UpdateStaging staging) =>
    _deleteDir(staging.scratchDir);

Future<void> _deleteDir(String path) async {
  try {
    final dir = Directory(path);
    if (dir.existsSync()) await dir.delete(recursive: true);
  } catch (error) {
    debugPrint('could not remove $path: $error');
  }
}

String _basename(String path) {
  final cut = path.lastIndexOf(RegExp(r'[/\\]'));
  return cut < 0 ? path : path.substring(cut + 1);
}

String _parentOf(String path) {
  final cut = path.lastIndexOf(RegExp(r'[/\\]'));
  return cut <= 0 ? path : path.substring(0, cut);
}

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:launch_at_startup/launch_at_startup.dart';

import '../../ui/core/strings/app_strings.dart';

/// "Start with the computer" — the tray menu's checkbox lives in
/// [KehaiTray] (backed by a [PrefsService] bool for its checked state);
/// this owns the platform mechanics behind toggling it.
///
/// Windows: `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` via the
/// `launch_at_startup` package (it shells out to `REG.exe` internally) —
/// genuinely works. Verify after enabling with:
/// `reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v Kehai`
///
/// Linux: `launch_at_startup` 0.0.1 (the only version resolvable alongside
/// device_info_plus — see pubspec.yaml's comment on the dependency) has no
/// Linux backend at all; calling into it there throws
/// `LateInitializationError`. So this writes the XDG autostart `.desktop`
/// file itself instead: `$XDG_CONFIG_HOME/autostart/kehai.desktop` (falling
/// back to `~/.config/autostart/`), the mechanism every real Linux desktop
/// environment's session manager (GNOME, KDE, XFCE, …) launches on login.
///
/// CAVEAT — WSLg: WSLg is not a desktop session with a login manager that
/// reads `~/.config/autostart/` — the file is written correctly, `Exec=`
/// correctly points at the running bundle's actual binary, `isEnabled()`
/// correctly reports it exists, but nothing on a WSLg-only machine ever
/// launches it. This is honest per-platform behavior, not a bug: autostart
/// here is for a real Linux desktop, and WSLg was only ever this project's
/// dev environment.
class AutostartService {
  AutostartService._();

  static final AutostartService instance = AutostartService._();

  static bool get isSupported =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux);

  bool _ready = false;

  /// Call once from `main()`, after `WidgetsFlutterBinding.ensureInitialized()`.
  /// Cheap and side-effect-free — it just points the Windows backend at this
  /// process's own resolved executable path; nothing is written to the
  /// registry or disk until [enable] is actually called.
  void bootstrap() {
    if (!isSupported || _ready) return;
    if (Platform.isWindows) {
      LaunchAtStartup.instance.setup(
        appName: AppStrings.appName,
        appPath: Platform.resolvedExecutable,
      );
    }
    _ready = true;
  }

  /// Whether autostart is actually registered with the OS right now — asked
  /// fresh rather than trusted from the pref, since the pref only records
  /// what the user last asked for through our UI. Best-effort: `false` on
  /// any failure, same as everything else in this file.
  Future<bool> isEnabledOnSystem() async {
    if (!isSupported) return false;
    try {
      if (Platform.isWindows) return await LaunchAtStartup.instance.isEnabled();
      return _desktopFile.existsSync();
    } catch (error) {
      debugPrint('autostart isEnabled check failed: $error');
      return false;
    }
  }

  Future<bool> enable() async {
    if (!isSupported) return false;
    try {
      if (Platform.isWindows) return await LaunchAtStartup.instance.enable();
      return _writeDesktopFile();
    } catch (error) {
      debugPrint('autostart enable failed: $error');
      return false;
    }
  }

  Future<bool> disable() async {
    if (!isSupported) return false;
    try {
      if (Platform.isWindows) return await LaunchAtStartup.instance.disable();
      return _deleteDesktopFile();
    } catch (error) {
      debugPrint('autostart disable failed: $error');
      return false;
    }
  }

  File get _desktopFile {
    final xdgConfig = Platform.environment['XDG_CONFIG_HOME'];
    final base = (xdgConfig != null && xdgConfig.isNotEmpty)
        ? xdgConfig
        : '${Platform.environment['HOME']}/.config';
    return File('$base/autostart/kehai.desktop');
  }

  bool _writeDesktopFile() {
    final file = _desktopFile;
    file.parent.createSync(recursive: true);
    // Exec points at the actual bundle binary this process is running from
    // right now — not a `flutter run` shim — so it stays correct wherever
    // the bundle ends up installed.
    file.writeAsStringSync(
      '[Desktop Entry]\n'
      'Type=Application\n'
      'Name=${AppStrings.appName}\n'
      'Comment=${AppStrings.trayTooltip}\n'
      'Exec="${Platform.resolvedExecutable}"\n'
      'Terminal=false\n'
      'X-GNOME-Autostart-enabled=true\n',
    );
    return true;
  }

  bool _deleteDesktopFile() {
    final file = _desktopFile;
    if (file.existsSync()) file.deleteSync();
    return true;
  }
}

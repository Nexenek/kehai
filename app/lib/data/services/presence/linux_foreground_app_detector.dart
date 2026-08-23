import 'dart:convert';
import 'dart:io';

/// The result of a Linux focused-window detection attempt: the window's
/// class/app_id — Wayland `app_id` under Hyprland/Sway, or the WM_CLASS
/// instance name under X11/XWayland — and its title. Mirrors Windows'
/// `ForegroundApp` (`windows_foreground_app_mapper.dart`) so both platforms
/// feed [ActivityMapper] the same shape; kept as a separate typedef since
/// "wmClass" is a more honest name than "exe" for what this side actually
/// has.
typedef LinuxForegroundWindow = ({String wmClass, String title});

/// Runs an external process the way `Process.run` does — injected so
/// [LinuxForegroundAppDetector] can be unit-tested with canned output
/// instead of a live compositor (kb/platform-desktop.md: Linux focused-app
/// detection is compositor-specific and per-environment, so tests feed
/// fixtures rather than shelling out for real).
typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// Detects the currently-focused window's class/app_id + title on Linux,
/// trying compositor-specific strategies in order (kb/features.md
/// "Focused-app status": "Linux X11 trivial, Wayland per-compositor only
/// (Hyprland/Sway IPC, KDE D-Bus; GNOME needs extension — degrade
/// honestly)"):
///
/// 1. **Hyprland** — guarded by `$HYPRLAND_INSTANCE_SIGNATURE` being set;
///    `hyprctl activewindow -j` (Process, since Hyprland has no D-Bus IPC).
/// 2. **Sway** — guarded by `$SWAYSOCK`; `swaymsg -t get_tree`, walked for
///    the focused node.
/// 3. **X11/XWayland** — guarded by `$DISPLAY`; `xdotool getactivewindow
///    getwindowname`/`getwindowclassname`, only reached when neither
///    Wayland-specific env var above was set.
/// 4. Otherwise `null` — most notably GNOME Wayland, which implements none
///    of the above (mutter#973) and gets an honest "we don't know" rather
///    than a guess.
///
/// Each strategy is tried **only** while its own env-var guard is
/// satisfied — once `$HYPRLAND_INSTANCE_SIGNATURE` says "you're on
/// Hyprland", this never falls through to Sway/X11 guesses, successful
/// poll or not. Within a strategy, a process that can't be spawned at all
/// (the binary genuinely isn't installed — a [ProcessException]) marks that
/// strategy permanently unavailable for the rest of this detector's
/// lifetime, so a missing `hyprctl`/`swaymsg`/`xdotool` costs one failed
/// spawn, not one every poll forever. A process that spawns fine but
/// reports "no active window" (non-zero exit, empty JSON) is *not* cached
/// as unavailable — that is a normal, transient state (nothing focused, a
/// window mid-close) worth re-checking next poll.
class LinuxForegroundAppDetector {
  LinuxForegroundAppDetector({
    Map<String, String>? environment,
    ProcessRunner? processRunner,
  }) : _environment = environment ?? Platform.environment,
       _run = processRunner ?? Process.run;

  final Map<String, String> _environment;
  final ProcessRunner _run;

  /// null = not yet known to be unavailable (still worth trying);
  /// false = the binary failed to spawn once — never try again.
  bool? _hyprlandAvailable;
  bool? _swayAvailable;
  bool? _xdotoolAvailable;

  Future<LinuxForegroundWindow?> detect() async {
    final hyprSignature = _environment['HYPRLAND_INSTANCE_SIGNATURE'];
    if (hyprSignature != null &&
        hyprSignature.isNotEmpty &&
        _hyprlandAvailable != false) {
      return _tryHyprland();
    }

    final swaySocket = _environment['SWAYSOCK'];
    if (swaySocket != null &&
        swaySocket.isNotEmpty &&
        _swayAvailable != false) {
      return _trySway();
    }

    final display = _environment['DISPLAY'];
    if (display != null && display.isNotEmpty && _xdotoolAvailable != false) {
      return _tryX11();
    }

    return null; // GNOME Wayland and friends — honest "we don't know".
  }

  Future<LinuxForegroundWindow?> _tryHyprland() async {
    try {
      final result = await _run('hyprctl', ['activewindow', '-j']);
      _hyprlandAvailable = true;
      if (result.exitCode != 0) return null;
      return LinuxForegroundAppParsers.parseHyprctlActiveWindow(
        _stdoutString(result),
      );
    } catch (_) {
      _hyprlandAvailable = false;
      return null;
    }
  }

  Future<LinuxForegroundWindow?> _trySway() async {
    try {
      final result = await _run('swaymsg', ['-t', 'get_tree']);
      _swayAvailable = true;
      if (result.exitCode != 0) return null;
      return LinuxForegroundAppParsers.parseSwayTree(_stdoutString(result));
    } catch (_) {
      _swayAvailable = false;
      return null;
    }
  }

  Future<LinuxForegroundWindow?> _tryX11() async {
    try {
      final classResult = await _run('xdotool', [
        'getactivewindow',
        'getwindowclassname',
      ]);
      final titleResult = await _run('xdotool', [
        'getactivewindow',
        'getwindowname',
      ]);
      _xdotoolAvailable = true;
      if (classResult.exitCode != 0) return null;
      final wmClass = _stdoutString(classResult).trim();
      if (wmClass.isEmpty) return null;
      final title = titleResult.exitCode == 0
          ? _stdoutString(titleResult).trim()
          : '';
      return (wmClass: wmClass, title: title);
    } catch (_) {
      _xdotoolAvailable = false;
      return null;
    }
  }

  static String _stdoutString(ProcessResult result) {
    final out = result.stdout;
    return out is String ? out : out.toString();
  }
}

/// Pure parsers for the JSON/text each Linux strategy above produces, kept
/// separate from the `Process.run` I/O so they're unit-testable with
/// hand-built fixtures — mirrors `WindowsForegroundAppMapper`.
class LinuxForegroundAppParsers {
  const LinuxForegroundAppParsers._();

  /// Parses `hyprctl activewindow -j` output. Hyprland prints `{}` (no
  /// `class` key) when nothing is focused — that, any non-JSON output, and
  /// a missing/empty `class` all map to null. `initialTitle`/`initialClass`
  /// are ignored in favour of the live `class`/`title` fields.
  static LinuxForegroundWindow? parseHyprctlActiveWindow(String stdout) {
    try {
      final decoded = jsonDecode(stdout);
      if (decoded is! Map) return null;
      final wmClass = decoded['class'];
      if (wmClass is! String || wmClass.isEmpty) return null;
      final title = decoded['title'];
      return (wmClass: wmClass, title: title is String ? title : '');
    } catch (_) {
      return null;
    }
  }

  /// Parses `swaymsg -t get_tree` output: walks the node tree (`nodes` +
  /// `floating_nodes`, depth-first) for the node with `"focused": true`.
  /// Native Wayland clients report `app_id`; XWayland clients report
  /// `window_properties.class` instead (`app_id` is null for those) — this
  /// tries `app_id` first and falls back to `window_properties.class`,
  /// mirroring how Sway itself distinguishes the two client types.
  static LinuxForegroundWindow? parseSwayTree(String stdout) {
    try {
      final root = jsonDecode(stdout);
      final node = _findFocused(root);
      if (node == null) return null;

      final appId = node['app_id'];
      String? wmClass = appId is String && appId.isNotEmpty ? appId : null;
      if (wmClass == null) {
        final props = node['window_properties'];
        if (props is Map) {
          final cls = props['class'];
          if (cls is String && cls.isNotEmpty) wmClass = cls;
        }
      }
      if (wmClass == null) return null;

      final name = node['name'];
      return (wmClass: wmClass, title: name is String ? name : '');
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _findFocused(dynamic node) {
    if (node is! Map) return null;
    if (node['focused'] == true) return node.cast<String, dynamic>();
    for (final key in const ['nodes', 'floating_nodes']) {
      final children = node[key];
      if (children is! List) continue;
      for (final child in children) {
        final found = _findFocused(child);
        if (found != null) return found;
      }
    }
    return null;
  }
}

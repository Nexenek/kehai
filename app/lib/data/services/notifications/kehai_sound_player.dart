import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'kehai_sound.dart';

/// Plays one of our bundled WAVs on desktop.
///
/// ## Why we play the sound ourselves
///
/// Notification toasts can't be relied on to carry a custom sound anywhere
/// but Android:
///
/// - **Linux**: the freedesktop notification spec has a `sound-file` hint,
///   but it's an *optional* server capability and most daemons (GNOME Shell
///   among them) simply ignore it. So we mark the toast silent and play the
///   file alongside it.
/// - **Windows**: WinRT toasts do support custom audio, but only via
///   `ms-appx:///` URIs — which means only for apps with a package identity,
///   i.e. installed from an MSIX. Kehai ships as a plain sideloaded folder
///   (kb/platform-desktop.md), so the toast falls back to the system default
///   ding. Same answer: silent toast, we play the file.
/// - **Android**: the opposite — a NotificationChannel's sound is the ONLY
///   sound Android will play for a notification, so this player is unused
///   there. See [KehaiNotifier]'s channel handling.
///
/// ## Why not a plugin
///
/// `audioplayers` was the obvious pick and was tried first. Its Linux
/// implementation is a GStreamer binding, so `flutter build linux` fails at
/// CMake time on any machine without `libgstreamer1.0-dev` — including this
/// one, and including a fresh clone for anyone else. For four 40 KB PCM WAVs
/// that's an absurd trade, so each platform uses the thing it already has:
///
/// - Windows: `winmm.dll`'s `PlaySound` — the Win32 WAV API, present since
///   Windows 95, asynchronous, one FFI call, no process spawn (and so no
///   console window flashing, which the PowerShell `Media.SoundPlayer`
///   approach would have caused in a GUI-subsystem app).
/// - Linux: whichever of `paplay` / `pw-play` / `aplay` / `ffplay` exists.
///   Every desktop that can show a notification at all has at least one.
///   None present → silence, which is the honest degrade.
///
/// Every path is best-effort: a sound that won't play must never take the
/// notification (or the app) down with it.
class KehaiSoundPlayer {
  KehaiSoundPlayer({@visibleForTesting Directory? cacheDirectory})
    : _cacheDirectory = cacheDirectory;

  final Directory? _cacheDirectory;

  /// Resolved WAV paths on disk, by sound id — populated on first play.
  final Map<String, String> _extracted = {};

  /// The Linux player we found last time. Probing costs a `which` per
  /// candidate, and the answer never changes within a session.
  String? _linuxPlayer;
  bool _linuxPlayerResolved = false;

  static bool get isSupported =>
      !kIsWeb && (Platform.isLinux || Platform.isWindows);

  /// Whether this machine has any way of playing a sound at all.
  ///
  /// Windows always does (winmm ships with the OS). Linux depends on one of
  /// the player binaries being installed, which is what the "sounds ♪"
  /// window uses to say so honestly rather than letting the user pick a
  /// sound that will never be heard.
  Future<bool> get isAudible async {
    if (!isSupported) return false;
    if (Platform.isWindows) return true;
    return await _resolveLinuxPlayer() != null;
  }

  /// Plays [sound], returning whether it actually got as far as handing the
  /// file to something. Never throws.
  Future<bool> play(KehaiSound sound) async {
    if (sound.isSilent || !isSupported) return false;
    try {
      final path = await _fileFor(sound);
      if (path == null) return false;
      if (Platform.isWindows) return _playWindows(path);
      return await _playLinux(path);
    } catch (error) {
      debugPrint('notification sound skipped: $error');
      return false;
    }
  }

  /// Writes the asset out to a real file once per process (the OS players
  /// all want a path, and the asset lives inside the bundle). Cached in the
  /// system temp dir rather than a Kehai-specific directory: these are
  /// regenerable, four of them, and nothing breaks if the OS sweeps them.
  Future<String?> _fileFor(KehaiSound sound) async {
    final cached = _extracted[sound.id];
    if (cached != null && File(cached).existsSync()) return cached;

    final dir = Directory(
      '${(_cacheDirectory ?? Directory.systemTemp).path}${Platform.pathSeparator}kehai_sounds',
    );
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final file = File('${dir.path}${Platform.pathSeparator}${sound.id}.wav');

    if (!file.existsSync()) {
      final data = await rootBundle.load(sound.assetPath);
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    }
    _extracted[sound.id] = file.path;
    return file.path;
  }

  // --- Windows: winmm PlaySound ------------------------------------------

  /// `SND_FILENAME | SND_ASYNC | SND_NODEFAULT` — read the path as a file,
  /// return immediately, and stay silent rather than substituting the system
  /// default beep if the file can't be played.
  static const int _sndAsync = 0x0001;
  static const int _sndNoDefault = 0x0002;
  static const int _sndFilename = 0x00020000;

  bool _playWindows(String path) {
    final playSound = _playSoundW ??= DynamicLibrary.open('winmm.dll')
        .lookupFunction<
          Int32 Function(Pointer<Utf16>, Pointer<Void>, Uint32),
          int Function(Pointer<Utf16>, Pointer<Void>, int)
        >('PlaySoundW');

    final buffer = path.toNativeUtf16();
    try {
      final ok = playSound(
        buffer,
        nullptr,
        _sndFilename | _sndAsync | _sndNoDefault,
      );
      return ok != 0;
    } finally {
      // SND_ASYNC copies the path before returning, so freeing now is safe.
      malloc.free(buffer);
    }
  }

  int Function(Pointer<Utf16>, Pointer<Void>, int)? _playSoundW;

  // --- Linux: whichever player is installed -------------------------------

  /// In preference order. `paplay` (PulseAudio/PipeWire-pulse) is on
  /// virtually every desktop; `pw-play` covers bare PipeWire; `aplay` covers
  /// bare ALSA; `ffplay` is the "well, ffmpeg is installed" catch-all.
  static const _linuxCandidates = <String, List<String>>{
    'paplay': [],
    'pw-play': [],
    'aplay': ['-q'],
    'ffplay': ['-nodisp', '-autoexit', '-loglevel', 'quiet'],
  };

  Future<bool> _playLinux(String path) async {
    final player = await _resolveLinuxPlayer();
    if (player == null) return false;
    // Detached: we don't care when it finishes and we never want to block a
    // notification on audio.
    await Process.start(player, [
      ..._linuxCandidates[player]!,
      path,
    ], mode: ProcessStartMode.detached);
    return true;
  }

  Future<String?> _resolveLinuxPlayer() async {
    if (_linuxPlayerResolved) return _linuxPlayer;
    _linuxPlayerResolved = true;
    for (final candidate in _linuxCandidates.keys) {
      try {
        final which = await Process.run('which', [candidate]);
        if (which.exitCode == 0) {
          _linuxPlayer = candidate;
          return candidate;
        }
      } catch (_) {
        // No `which` at all — give up on the whole chain quietly.
        break;
      }
    }
    debugPrint(
      'no audio player found (tried ${_linuxCandidates.keys.join(", ")}) '
      '— notifications will be silent',
    );
    return null;
  }
}

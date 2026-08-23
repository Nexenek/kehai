/// Turns a raw process/package identifier into the "what app they're
/// focused on" activity line the partner card shows (kb/features.md's
/// "Focused-app status": "friendly-name mapping layer (exe/package -> '
/// gaming', 'in Blender') — never leak raw process names by default").
///
/// Pure and platform-agnostic on purpose — no MethodChannel, no Flutter
/// widget imports — so it's trivially unit-testable and shared between the
/// Windows (`exe` name) and Android (package id) presence paths, which both
/// hand it a lowercased identifier and get back either a ready-to-show
/// label or null.
///
/// Precedence lives one level up, in [resolveAmbientLine]
/// (now_playing > activity > presence): a device that's actively playing
/// music always wins over whatever app is merely focused, which is why
/// music players (Spotify, YouTube Music, ...) are deliberately absent from
/// both tables below — now-playing already covers them better, and mapping
/// e.g. a *paused* Spotify to "on Spotify" here would just be a worse,
/// redundant version of that signal.
class ActivityMapper {
  const ActivityMapper._();

  /// Maps a Windows foreground process's image name (as
  /// `WindowsForegroundAppMapper`/`windows/runner/presence_channel.cpp`
  /// hand it: lowercased, `.exe` already stripped) to a friendly activity
  /// label. Null/empty input, or an exe with no table entry when
  /// [shareUnknown] is false, both return null — "nothing to say", not "say
  /// nothing useful."
  ///
  /// [shareUnknown] is the `shareUnknownApps` opt-in
  /// (kb/features.md/PrefsService): when on, an unrecognized exe still gets
  /// a cleaned-up, title-cased guess instead of staying silent.
  static String? mapWindowsExe(String? exe, {bool shareUnknown = false}) {
    if (exe == null) return null;
    final key = exe.trim().toLowerCase();
    if (key.isEmpty) return null;
    final hit = _windowsExeTable[key];
    if (hit != null) return hit;
    return shareUnknown ? _titleCase(key) : null;
  }

  /// Maps a Linux window's class/app_id (as
  /// `LinuxForegroundAppDetector`/`linux_foreground_app_detector.dart` hand
  /// it: lowercased WM_CLASS instance name on X11/XWayland, or the Wayland
  /// `app_id` under Hyprland/Sway) to a friendly activity label. Same
  /// null/[shareUnknown] rules as [mapWindowsExe].
  static String? mapLinuxClass(String? wmClass, {bool shareUnknown = false}) {
    if (wmClass == null) return null;
    final key = wmClass.trim().toLowerCase();
    if (key.isEmpty) return null;
    final hit = _linuxClassTable[key];
    if (hit != null) return hit;
    return shareUnknown ? _titleCase(key) : null;
  }

  /// Maps an Android package id (e.g. `com.instagram.android`) to a
  /// friendly activity label. Same null/[shareUnknown] rules as
  /// [mapWindowsExe]; the unknown-mode fallback title-cases the package's
  /// last path segment (mirrors
  /// `MediaSessionSnapshot.prettyPackageName`'s last-resort guess) rather
  /// than the whole dotted id, which reads better ("Trill", not "Com Ss
  /// Android Ugc Trill").
  static String? mapAndroidPackage(
    String? package, {
    bool shareUnknown = false,
  }) {
    if (package == null) return null;
    final key = package.trim().toLowerCase();
    if (key.isEmpty) return null;
    final hit = _androidPackageTable[key];
    if (hit != null) return hit;
    return shareUnknown ? _titleCase(_lastSegment(key)) : null;
  }

  /// Refines the generic "browsing ☁" label using the focused window's
  /// title — Windows' `getForegroundApp` and the Linux detection chain both
  /// hand one over; Android (package-only, no window title) never calls
  /// this. A no-op for anything else: it only ever touches a label that's
  /// already the generic browser one, never a specifically-mapped app
  /// (`in Blender` stays `in Blender` even if its title happens to
  /// contain "GitHub").
  ///
  /// PRIVACY RULE: this only ever returns one of the fixed labels below —
  /// never the title itself, or any substring of it. Titles carry video
  /// names, document names, search queries; the whole point of the
  /// friendly-label layer (kb/features.md "Focused-app status": "never leak
  /// raw process names by default") is that the partner sees "watching
  /// YouTube", not *which* video. If a new pattern is ever added here it
  /// must map to another fixed label, full stop.
  ///
  /// Patterns are matched case-insensitively and, for the two "ends with
  /// site name after a separator" cases (YouTube, Google Docs), tolerate
  /// hyphen/en dash/em dash — browsers on different locales (Polish
  /// included) render the title separator differently ("Song — YouTube" vs
  /// "Song - YouTube").
  static String? refineBrowserLabel(String? label, String? title) {
    if (label != _browsing) return label;
    if (title == null || title.trim().isEmpty) return label;

    if (_youtubeSuffix.hasMatch(title)) return 'watching YouTube';
    if (title.toLowerCase().contains('netflix')) return 'watching Netflix';
    if (title.toLowerCase().contains('twitch')) return 'watching Twitch';
    if (_googleDocsSuffix.hasMatch(title)) return 'writing ✍\uFE0E';
    if (title.toLowerCase().contains('github')) return _coding;
    if (title.toLowerCase().contains('reddit')) return 'scrolling Reddit';
    if (title.toLowerCase().contains('wikipedia')) return 'reading';

    return label;
  }

  // " - YouTube" / " – YouTube" / " — YouTube" (hyphen/en dash/em dash,
  // optional surrounding whitespace) at the end of the title.
  static final RegExp _youtubeSuffix = RegExp(
    r'[-–—]\s*YouTube\s*$',
    caseSensitive: false,
  );

  static final RegExp _googleDocsSuffix = RegExp(
    r'[-–—]\s*Google Docs\s*$',
    caseSensitive: false,
  );

  static String _lastSegment(String package) {
    final parts = package.split('.').where((p) => p.isNotEmpty).toList();
    return parts.isEmpty ? package : parts.last;
  }

  /// `some_weird-app.name` -> `Some Weird App Name`. Best-effort cleanup for
  /// the `shareUnknown` fallback — never shown unless the user opted into
  /// it, so "good enough to be readable" is the bar, not "perfect".
  static String _titleCase(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[_\-.]+'), ' ').trim();
    if (cleaned.isEmpty) return raw;
    return cleaned
        .split(RegExp(r'\s+'))
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  // Coding / creative tools.
  static const _coding = 'coding ⌨\uFE0E';
  static const _drawing = 'drawing';
  static const _browsing = 'browsing ☁\uFE0E';

  static const _windowsExeTable = <String, String>{
    // Coding.
    'code': _coding,
    'devenv': _coding,
    'idea64': _coding,
    'pycharm64': _coding,
    'webstorm64': _coding,
    'clion64': _coding,
    'rider64': _coding,
    'studio64': _coding,
    'sublime_text': _coding,
    'windowsterminal': _coding,

    // Creative.
    'blender': 'in Blender',
    'krita': _drawing,
    'photoshop': _drawing,
    'illustrator': _drawing,
    'clipstudiopaint': _drawing,

    // Chat.
    'discord': 'chatting on Discord ✉\uFE0E',
    'slack': 'chatting on Slack ✉\uFE0E',
    'telegram': 'chatting on Telegram ✉\uFE0E',
    'whatsapp': 'chatting on WhatsApp ✉\uFE0E',
    'signal': 'chatting on Signal ✉\uFE0E',

    // Gaming.
    'steam': 'gaming',
    'epicgameslauncher': 'gaming',
    'riotclientservices': 'gaming',
    'battle.net': 'gaming',
    'leagueclient': 'gaming',
    'valorant-win64-shipping': 'gaming',
    'csgo': 'gaming',
    'cs2': 'gaming',
    'overwatch': 'gaming',
    'eldenring': 'gaming',
    'gta5': 'gaming',
    'minecraftlauncher': 'gaming',

    // Streaming.
    'obs64': 'streaming ✧',
    'obs32': 'streaming ✧',
    'streamlabs obs': 'streaming ✧',

    // Office / writing.
    'winword': 'writing ✍\uFE0E',
    'excel': 'crunching numbers 📊',
    'powerpnt': 'making slides 📊',

    // Browsers — mapped generically; the ambient-line precedence already
    // puts now_playing above activity, so a browser tab playing music never
    // gets shadowed by "browsing ☁".
    'chrome': _browsing,
    'msedge': _browsing,
    'firefox': _browsing,
    'brave': _browsing,
    'opera': _browsing,
    'vivaldi': _browsing,

    // Music apps stay unmapped on purpose — see the class doc comment.
    // 'spotify': deliberately absent.
  };

  static const _androidPackageTable = <String, String>{
    // Chat.
    'com.discord': 'chatting on Discord ✉\uFE0E',
    'com.slack': 'chatting on Slack ✉\uFE0E',
    'org.telegram.messenger': 'chatting on Telegram ✉\uFE0E',
    'com.whatsapp': 'chatting on WhatsApp ✉\uFE0E',
    'org.thoughtcrime.securesms': 'chatting on Signal ✉\uFE0E',

    // Meetings.
    'us.zoom.videomeetings': 'in a meeting',
    'com.google.android.apps.meetings': 'in a meeting',
    'com.microsoft.teams': 'in a meeting',

    // Short video / social.
    'com.ss.android.ugc.trill': 'scrolling TikTok',
    'com.zhiliaoapp.musically': 'scrolling TikTok',
    'com.instagram.android': 'on Instagram',
    'com.facebook.katana': 'on Facebook',
    'com.snapchat.android': 'on Snapchat',
    'com.pinterest': 'on Pinterest',
    'com.reddit.frontpage': 'browsing Reddit',
    'com.twitter.android': 'on Twitter',
    'com.x': 'on Twitter',

    // Video.
    'com.google.android.youtube': 'watching YouTube',
    'com.netflix.mediaclient': 'watching Netflix',

    // Writing / office.
    'com.google.android.apps.docs.editors.docs': 'writing ✍\uFE0E',
    'com.microsoft.office.word': 'writing ✍\uFE0E',
    'com.google.android.gm': 'checking email 📧',

    // Gaming.
    'com.king.candycrushsaga': 'gaming',
    'com.supercell.clashofclans': 'gaming',
    'com.mojang.minecraftpe': 'gaming',
    'com.roblox.client': 'gaming',
    'com.mihoyo.genshinimpact': 'gaming',

    // Browsers.
    'com.android.chrome': _browsing,
    'org.mozilla.firefox': _browsing,
    'com.brave.browser': _browsing,
    'com.microsoft.emmx': _browsing,
    'com.opera.browser': _browsing,

    // Music apps stay unmapped on purpose — see the class doc comment.
    // 'com.spotify.music': deliberately absent.
    // 'com.google.android.apps.youtube.music': deliberately absent.
  };

  /// Common Linux binary/WM_CLASS/app_id names
  /// (`LinuxForegroundAppDetector`'s Hyprland `class` / Sway `app_id` /
  /// xdotool `getwindowclassname` results, all already lowercased by the
  /// detector before this table is consulted).
  static const _linuxClassTable = <String, String>{
    // Coding.
    'code': _coding,
    'code - oss': _coding,
    'code-oss': _coding,
    'codium': _coding,
    'code-insiders': _coding,
    'jetbrains-idea': _coding,
    'jetbrains-idea-ce': _coding,
    'jetbrains-pycharm': _coding,
    'jetbrains-clion': _coding,
    'jetbrains-webstorm': _coding,
    'jetbrains-studio': _coding,
    'sublime_text': _coding,

    // Creative.
    'blender': 'in Blender',
    'krita': _drawing,
    'gimp': _drawing,
    'inkscape': _drawing,

    // Chat.
    'discord': 'chatting on Discord ✉\uFE0E',
    'discordcanary': 'chatting on Discord ✉\uFE0E',
    'discordptb': 'chatting on Discord ✉\uFE0E',
    'slack': 'chatting on Slack ✉\uFE0E',
    'telegram-desktop': 'chatting ✉\uFE0E',
    'signal': 'chatting on Signal ✉\uFE0E',

    // Gaming.
    'steam': 'gaming',
    'steam_app_default': 'gaming',
    'lutris': 'gaming',
    'heroic': 'gaming',

    // Streaming.
    'obs': 'streaming ✧',
    'com.obsproject.studio': 'streaming ✧',

    // Browsers — mapped generically; [refineBrowserLabel] refines further
    // from the window title, same as Windows.
    'firefox': _browsing,
    'firefox-esr': _browsing,
    'chromium': _browsing,
    'chromium-browser': _browsing,
    'google-chrome': _browsing,
    'brave-browser': _browsing,
    'vivaldi-stable': _browsing,

    // Music apps stay unmapped on purpose — see the class doc comment.
    // 'spotify': deliberately absent.
  };
}

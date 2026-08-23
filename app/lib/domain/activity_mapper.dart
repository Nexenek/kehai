/// Turns a raw process/package identifier into the "what app they're
/// focused on" activity line the partner card shows (kb/features.md's
/// "Focused-app status": "friendly-name mapping layer (exe/package -> '🎮
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
  static const _coding = 'coding ⌨';
  static const _drawing = 'drawing 🎨';

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
    'blender': 'in Blender 🎨',
    'krita': _drawing,
    'photoshop': _drawing,
    'illustrator': _drawing,
    'clipstudiopaint': _drawing,

    // Chat.
    'discord': 'chatting ✉',
    'slack': 'chatting ✉',
    'telegram': 'chatting ✉',
    'whatsapp': 'chatting ✉',
    'signal': 'chatting ✉',

    // Gaming.
    'steam': 'gaming 🎮',
    'epicgameslauncher': 'gaming 🎮',
    'riotclientservices': 'gaming 🎮',
    'battle.net': 'gaming 🎮',
    'leagueclient': 'gaming 🎮',
    'valorant-win64-shipping': 'gaming 🎮',
    'csgo': 'gaming 🎮',
    'cs2': 'gaming 🎮',
    'overwatch': 'gaming 🎮',
    'eldenring': 'gaming 🎮',
    'gta5': 'gaming 🎮',
    'minecraftlauncher': 'gaming 🎮',

    // Streaming.
    'obs64': 'streaming ✧',
    'obs32': 'streaming ✧',
    'streamlabs obs': 'streaming ✧',

    // Office / writing.
    'winword': 'writing ✍',
    'excel': 'crunching numbers 📊',
    'powerpnt': 'making slides 📊',

    // Browsers — mapped generically; the ambient-line precedence already
    // puts now_playing above activity, so a browser tab playing music never
    // gets shadowed by "browsing ☁".
    'chrome': 'browsing ☁',
    'msedge': 'browsing ☁',
    'firefox': 'browsing ☁',
    'brave': 'browsing ☁',
    'opera': 'browsing ☁',
    'vivaldi': 'browsing ☁',

    // Music apps stay unmapped on purpose — see the class doc comment.
    // 'spotify': deliberately absent.
  };

  static const _androidPackageTable = <String, String>{
    // Chat.
    'com.discord': 'chatting ✉',
    'com.slack': 'chatting ✉',
    'org.telegram.messenger': 'chatting ✉',
    'com.whatsapp': 'chatting ✉',
    'org.thoughtcrime.securesms': 'chatting ✉',

    // Meetings.
    'us.zoom.videomeetings': 'in a meeting 🎥',
    'com.google.android.apps.meetings': 'in a meeting 🎥',
    'com.microsoft.teams': 'in a meeting 🎥',

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
    'com.netflix.mediaclient': 'watching Netflix 🎬',

    // Writing / office.
    'com.google.android.apps.docs.editors.docs': 'writing ✍',
    'com.microsoft.office.word': 'writing ✍',
    'com.google.android.gm': 'checking email 📧',

    // Gaming.
    'com.king.candycrushsaga': 'gaming 🎮',
    'com.supercell.clashofclans': 'gaming 🎮',
    'com.mojang.minecraftpe': 'gaming 🎮',
    'com.roblox.client': 'gaming 🎮',
    'com.mihoyo.genshinimpact': 'gaming 🎮',

    // Browsers.
    'com.android.chrome': 'browsing ☁',
    'org.mozilla.firefox': 'browsing ☁',
    'com.brave.browser': 'browsing ☁',
    'com.microsoft.emmx': 'browsing ☁',
    'com.opera.browser': 'browsing ☁',

    // Music apps stay unmapped on purpose — see the class doc comment.
    // 'com.spotify.music': deliberately absent.
    // 'com.google.android.apps.youtube.music': deliberately absent.
  };
}

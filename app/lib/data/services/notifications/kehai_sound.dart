/// The four bundled sounds, plus silence.
///
/// All four are synthesized by `tool/generate_notification_sounds.py` (that
/// script, not the .wav files, is the source of truth) and shipped twice: as
/// a Flutter asset for desktop, and as an `android/app/src/main/res/raw/`
/// resource for Android, whose NotificationChannel sounds are resolved by
/// the system UI process and can't reach into our asset bundle.
enum KehaiSound {
  /// Ascending square arpeggio (C6-E6-G6-C7), 0.26s. Goes *up*.
  sparkle('sparkle', 'sparkle ✧'),

  /// One soft square blip with a downward bend, 0.09s.
  pop('pop', 'pop ·'),

  /// Two triangle notes, G5 → C6, faintly bell-ish, 0.44s.
  chime('chime', 'chime ♪'),

  /// Low 110 Hz triangle wobbling at 17 Hz, 0.46s. The gentle one.
  purr('purr', 'purr ~'),

  /// No sound at all — the notification still appears.
  silent('silent', 'silent');

  const KehaiSound(this.id, this.label);

  /// Persisted value (PrefsService) and the stem of both file names. Never
  /// localize.
  final String id;

  /// What the picker shows.
  final String label;

  bool get isSilent => this == KehaiSound.silent;

  /// Path inside the Flutter asset bundle. Meaningless for [silent].
  String get assetPath => 'assets/sounds/$id.wav';

  /// Android `res/raw` resource name (no extension), prefixed so it can
  /// never collide with a library resource.
  String get androidResource => 'kehai_$id';

  /// Anything unrecognized — a pref written by a newer build, a hand-edited
  /// value — reads back as the caller's default rather than throwing.
  static KehaiSound byId(String? id, {required KehaiSound fallback}) {
    if (id == null) return fallback;
    for (final sound in KehaiSound.values) {
      if (sound.id == id) return sound;
    }
    return fallback;
  }

  /// The order the picker offers them in: the four voices, then silence.
  static const List<KehaiSound> pickable = KehaiSound.values;
}

/// The four things Kehai will interrupt you for.
///
/// Deliberately short. Everything else the app knows about your person —
/// their mood, what they're listening to, whether they're at their computer,
/// where they are — is *ambient*: it belongs in the partner window you
/// glance at, and turning any of it into a notification would make the app
/// something you have to manage rather than something you have.
///
/// **Mood changes specifically do NOT notify.** They're the highest-frequency
/// signal in the app and the least actionable one; a buzz every time your
/// partner switches from "cozy" to "sleepy" would train you to mute Kehai
/// within a week, which costs you the pings — the ones that actually mean
/// "come here, I'm thinking about you". Ambient stays ambient.
enum KehaiEventKind {
  /// The headline: a one-tap ping arrived (kb/features.md's "High LDR value").
  ping('ping'),

  /// They drew you something.
  doodle('doodle'),

  /// They sent a photo.
  instant('instant'),

  /// Both of you have now answered today's question, so it just opened up.
  reveal('reveal');

  const KehaiEventKind(this.id);

  /// Persisted value (the per-event sound pref key) and the Android channel
  /// id stem. Never localize.
  final String id;

  /// The sound this event uses out of the box. The ping gets the one that
  /// goes up; doodles get the smallest, least intrusive blip; photos and the
  /// reveal share the chime because they're the two "there's something to go
  /// look at" events.
  KehaiSound get defaultSound => switch (this) {
    KehaiEventKind.ping => KehaiSound.sparkle,
    KehaiEventKind.doodle => KehaiSound.pop,
    KehaiEventKind.instant => KehaiSound.chime,
    KehaiEventKind.reveal => KehaiSound.chime,
  };

  static KehaiEventKind? byId(String id) {
    for (final kind in KehaiEventKind.values) {
      if (kind.id == id) return kind;
    }
    return null;
  }
}

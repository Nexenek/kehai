import 'package:flutter/foundation.dart';

import '../../../../data/services/notifications/kehai_notifier.dart';
import '../../../../data/services/notifications/kehai_sound.dart';

/// Drives the "sounds ♪" window: which sound each event type uses, and
/// preview-on-tap.
///
/// Thin on purpose — [KehaiNotifier] already owns both the persistence (via
/// PrefsService) and the platform-specific business of making a sound
/// happen, so this only holds the picker's in-flight state.
class SoundSettingsViewModel extends ChangeNotifier {
  SoundSettingsViewModel({required KehaiNotifier notifier})
    : _notifier = notifier;

  final KehaiNotifier _notifier;

  /// The row currently being previewed, so the picker can show which one is
  /// making the noise (and so a second tap while it's still playing doesn't
  /// stack previews).
  KehaiEventKind? previewing;

  /// Whether a chosen sound will actually be heard on this machine. Null
  /// until [init] resolves — the window says nothing while it doesn't know,
  /// rather than flashing a warning it might immediately retract.
  bool? audible;

  /// Probes for a working audio path (see [KehaiNotifier.soundsAudible]). A
  /// Linux box with no `paplay`/`aplay`/`ffplay` can show notifications but
  /// not sound them, and the window says so instead of letting someone pick
  /// a sound they'll never hear.
  Future<void> init() async {
    final result = await _notifier.soundsAudible;
    audible = result;
    if (hasListeners) notifyListeners();
  }

  KehaiSound soundFor(KehaiEventKind kind) => _notifier.soundFor(kind);

  /// Picks [sound] for [kind] and immediately plays it — choosing and
  /// hearing are the same gesture, because a picker you have to press
  /// "preview" on separately is a picker nobody auditions.
  Future<void> choose(KehaiEventKind kind, KehaiSound sound) async {
    await _notifier.setSound(kind, sound);
    notifyListeners();
    if (sound.isSilent) return;

    previewing = kind;
    notifyListeners();
    try {
      await _notifier.preview(kind, sound);
    } finally {
      if (previewing == kind) {
        previewing = null;
        if (hasListeners) notifyListeners();
      }
    }
  }
}

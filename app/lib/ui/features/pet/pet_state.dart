/// Pure derivation of the shared pet's mood from two timestamps and the
/// local clock. No storage, no timers, no server state — feed the pet and
/// its state changes because `fed_at` moved, not because a counter was
/// decremented somewhere.
///
/// The rule that shapes every line in here (kb/features.md anti-features):
/// **"The pet gets 'sleepy', never dies."** There is no fail state, no
/// scolding, and no guilt. The hungriest the copy ever gets is wistful —
/// "dreaming of snacks…" — and the pet always waits patiently.
library;

import 'package:flutter/foundation.dart';

import '../../core/strings/app_strings.dart';

/// How long ago the last snack was.
enum PetHunger {
  /// Fed less than [PetStateRules.fullFor] ago.
  full,

  /// Fed between [PetStateRules.fullFor] and [PetStateRules.peckishUntil]
  /// ago — interested in food, perfectly content without it.
  peckish,

  /// Fed longer than [PetStateRules.peckishUntil] ago. Still fine. Still
  /// waiting. Never punished.
  hungry,
}

/// How long ago the last cuddle was.
enum PetCuddles { cozy, wantsCuddles }

/// What the painter draws on the face.
enum PetExpression { happy, content, wistful, sleepy }

/// The thresholds, in one place so tests and copy agree.
class PetStateRules {
  const PetStateRules._();

  static const fullFor = Duration(hours: 8);
  static const peckishUntil = Duration(hours: 24);
  static const cozyFor = Duration(hours: 12);

  /// Local wall-clock nap window: 23:00 up to (not including) 07:00.
  static const sleepFromHour = 23;
  static const wakeHour = 7;
}

/// The derived mood: hunger + cuddles + whether it's the middle of the
/// night. Everything the UI needs, computed, never stored.
@immutable
class PetState {
  const PetState({
    required this.hunger,
    required this.cuddles,
    required this.sleepy,
  });

  final PetHunger hunger;
  final PetCuddles cuddles;

  /// True between 23:00 and 07:00 local — the pet naps (zzZ, closed eyes)
  /// regardless of hunger. This is the only "bad" state that exists.
  final bool sleepy;

  PetExpression get expression {
    if (sleepy) return PetExpression.sleepy;
    return switch (hunger) {
      PetHunger.full => PetExpression.happy,
      PetHunger.peckish => PetExpression.content,
      PetHunger.hungry => PetExpression.wistful,
    };
  }

  /// Blush cheeks when recently cuddled — a second, non-color-only signal
  /// backs it up in [line] (design-language.md accessibility floor).
  bool get blushing => cuddles == PetCuddles.cozy && !sleepy;

  /// The one-line status under the sprite, in kb voice.
  String get line {
    if (sleepy) {
      return hunger == PetHunger.hungry
          ? AppStrings.petLineSleepyHungry
          : AppStrings.petLineSleepy;
    }
    final wantsCuddles = cuddles == PetCuddles.wantsCuddles;
    return switch (hunger) {
      PetHunger.full =>
        wantsCuddles
            ? AppStrings.petLineFullCuddles
            : AppStrings.petLineFullCozy,
      PetHunger.peckish =>
        wantsCuddles
            ? AppStrings.petLinePeckishCuddles
            : AppStrings.petLinePeckishCozy,
      PetHunger.hungry =>
        wantsCuddles
            ? AppStrings.petLineHungryCuddles
            : AppStrings.petLineHungryCozy,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is PetState &&
      other.hunger == hunger &&
      other.cuddles == cuddles &&
      other.sleepy == sleepy;

  @override
  int get hashCode => Object.hash(hunger, cuddles, sleepy);

  @override
  String toString() => 'PetState($hunger, $cuddles, sleepy: $sleepy)';
}

/// Derives the pet's state from the last snack ([fedAt]) and last cuddle
/// ([petAt]) against [now] (defaults to [DateTime.now], injectable so the
/// whole thing is testable without waiting eight hours).
///
/// Null / future timestamps degrade gently: a null reads as "never", and a
/// clock that's ahead of the record (partner's device skew) clamps to zero
/// age instead of going negative.
PetState derivePetState({DateTime? fedAt, DateTime? petAt, DateTime? now}) {
  final clock = now ?? DateTime.now();

  return PetState(
    hunger: _hunger(_ageOf(fedAt, clock)),
    cuddles: _cuddles(_ageOf(petAt, clock)),
    sleepy: isPetSleepy(clock),
  );
}

/// True while the local wall clock is inside the nap window (23:00–07:00).
bool isPetSleepy(DateTime now) =>
    now.hour >= PetStateRules.sleepFromHour ||
    now.hour < PetStateRules.wakeHour;

/// Null = "never", so it reads as the oldest possible age rather than as
/// "just now" (which would make an un-stamped pet look freshly fed).
Duration? _ageOf(DateTime? at, DateTime now) {
  if (at == null) return null;
  final age = now.difference(at);
  return age.isNegative ? Duration.zero : age;
}

PetHunger _hunger(Duration? age) {
  if (age == null) return PetHunger.hungry;
  if (age < PetStateRules.fullFor) return PetHunger.full;
  if (age <= PetStateRules.peckishUntil) return PetHunger.peckish;
  return PetHunger.hungry;
}

PetCuddles _cuddles(Duration? age) => age != null && age < PetStateRules.cozyFor
    ? PetCuddles.cozy
    : PetCuddles.wantsCuddles;

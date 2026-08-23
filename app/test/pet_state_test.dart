import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/ui/core/strings/app_strings.dart';
import 'package:couples_app/ui/features/pet/pet_state.dart';

/// A fixed mid-afternoon "now" so nothing here accidentally lands inside the
/// 23:00–07:00 nap window.
final _afternoon = DateTime(2026, 8, 23, 15);

PetState _at({Duration? fedAgo, Duration? petAgo, DateTime? now}) {
  final clock = now ?? _afternoon;
  return derivePetState(
    fedAt: fedAgo == null ? null : clock.subtract(fedAgo),
    petAt: petAgo == null ? null : clock.subtract(petAgo),
    now: clock,
  );
}

void main() {
  group('hunger, derived from fed_at', () {
    test('just fed is full', () {
      expect(_at(fedAgo: Duration.zero).hunger, PetHunger.full);
      expect(
        _at(fedAgo: const Duration(hours: 7, minutes: 59)).hunger,
        PetHunger.full,
      );
    });

    test('the 8h boundary tips into peckish', () {
      expect(_at(fedAgo: const Duration(hours: 8)).hunger, PetHunger.peckish);
      expect(
        _at(fedAgo: const Duration(hours: 23, minutes: 59)).hunger,
        PetHunger.peckish,
      );
    });

    test('exactly 24h is still peckish; past it is hungry', () {
      expect(_at(fedAgo: const Duration(hours: 24)).hunger, PetHunger.peckish);
      expect(
        _at(fedAgo: const Duration(hours: 24, minutes: 1)).hunger,
        PetHunger.hungry,
      );
      expect(_at(fedAgo: const Duration(days: 30)).hunger, PetHunger.hungry);
    });

    test('never fed reads as hungry, not as freshly fed', () {
      expect(_at().hunger, PetHunger.hungry);
    });

    test('a fed_at in the future (clock skew) clamps to just-fed', () {
      final state = derivePetState(
        fedAt: _afternoon.add(const Duration(hours: 3)),
        petAt: _afternoon,
        now: _afternoon,
      );
      expect(state.hunger, PetHunger.full);
    });
  });

  group('cuddles, derived from pet_at', () {
    test('petted within 12h is cozy', () {
      expect(_at(petAgo: Duration.zero).cuddles, PetCuddles.cozy);
      expect(
        _at(petAgo: const Duration(hours: 11, minutes: 59)).cuddles,
        PetCuddles.cozy,
      );
    });

    test('12h or longer wants cuddles', () {
      expect(
        _at(petAgo: const Duration(hours: 12)).cuddles,
        PetCuddles.wantsCuddles,
      );
      expect(_at().cuddles, PetCuddles.wantsCuddles);
    });
  });

  group('the nap window', () {
    test('23:00 through 06:59 local is sleepy', () {
      for (final hour in [23, 0, 3, 6]) {
        final now = DateTime(2026, 8, 23, hour, 30);
        expect(isPetSleepy(now), isTrue, reason: 'hour $hour');
        expect(_at(fedAgo: Duration.zero, now: now).sleepy, isTrue);
      }
    });

    test('07:00 through 22:59 local is awake', () {
      for (final hour in [7, 12, 22]) {
        final now = DateTime(2026, 8, 23, hour, 30);
        expect(isPetSleepy(now), isFalse, reason: 'hour $hour');
        expect(_at(fedAgo: Duration.zero, now: now).sleepy, isFalse);
      }
    });

    test('sleeping overrides the expression whatever the hunger', () {
      final night = DateTime(2026, 8, 24, 2);
      final starving = _at(fedAgo: const Duration(days: 5), now: night);
      expect(starving.expression, PetExpression.sleepy);
      expect(starving.blushing, isFalse);
    });
  });

  group('expression', () {
    test('maps hunger while awake', () {
      expect(_at(fedAgo: Duration.zero).expression, PetExpression.happy);
      expect(
        _at(fedAgo: const Duration(hours: 10)).expression,
        PetExpression.content,
      );
      expect(
        _at(fedAgo: const Duration(days: 2)).expression,
        PetExpression.wistful,
      );
    });

    test('blushes only when recently cuddled and awake', () {
      expect(_at(petAgo: const Duration(hours: 1)).blushing, isTrue);
      expect(_at(petAgo: const Duration(hours: 20)).blushing, isFalse);
    });
  });

  group('copy — every line is gentle, none is a fail state', () {
    test('picks the right line for each combination', () {
      expect(
        _at(fedAgo: Duration.zero, petAgo: Duration.zero).line,
        AppStrings.petLineFullCozy,
      );
      expect(
        _at(fedAgo: Duration.zero, petAgo: const Duration(days: 1)).line,
        AppStrings.petLineFullCuddles,
      );
      expect(
        _at(fedAgo: const Duration(hours: 9), petAgo: Duration.zero).line,
        AppStrings.petLinePeckishCozy,
      );
      expect(
        _at(
          fedAgo: const Duration(hours: 9),
          petAgo: const Duration(days: 1),
        ).line,
        AppStrings.petLinePeckishCuddles,
      );
      expect(
        _at(fedAgo: const Duration(days: 3), petAgo: Duration.zero).line,
        AppStrings.petLineHungryCozy,
      );
      expect(
        _at(
          fedAgo: const Duration(days: 3),
          petAgo: const Duration(days: 3),
        ).line,
        AppStrings.petLineHungryCuddles,
      );
    });

    test('asleep says zzZ, and only mentions snacks wistfully', () {
      final night = DateTime(2026, 8, 24, 1);
      expect(
        _at(fedAgo: Duration.zero, now: night).line,
        AppStrings.petLineSleepy,
      );
      expect(
        _at(fedAgo: const Duration(days: 4), now: night).line,
        AppStrings.petLineSleepyHungry,
      );
    });

    test('no state line contains guilt/urgency words — the anti-feature rule '
        'in kb/features.md ("the pet gets sleepy, never dies")', () {
      const forbidden = [
        'die',
        'dead',
        'starv',
        'sick',
        'sad',
        'lonely',
        'neglect',
        'forgot',
        'weak',
        'hurry',
        'now!',
        'urgent',
        'warning',
        'last chance',
      ];
      final lines = [
        AppStrings.petLineFullCozy,
        AppStrings.petLineFullCuddles,
        AppStrings.petLinePeckishCozy,
        AppStrings.petLinePeckishCuddles,
        AppStrings.petLineHungryCozy,
        AppStrings.petLineHungryCuddles,
        AppStrings.petLineSleepy,
        AppStrings.petLineSleepyHungry,
        AppStrings.petUnavailable,
        AppStrings.petActionFailed,
      ];
      for (final line in lines) {
        for (final word in forbidden) {
          expect(
            line.toLowerCase().contains(word),
            isFalse,
            reason: '"$line" contains "$word"',
          );
        }
      }
    });
  });

  test('equality is by value, so widgets can compare states cheaply', () {
    expect(_at(fedAgo: Duration.zero), _at(fedAgo: const Duration(hours: 1)));
    expect(
      _at(fedAgo: Duration.zero),
      isNot(_at(fedAgo: const Duration(hours: 10))),
    );
  });
}

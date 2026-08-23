import 'package:flutter_test/flutter_test.dart';

import 'package:couples_app/ui/features/pings/ping_send_logic.dart';

void main() {
  final t0 = DateTime(2026, 8, 24, 12, 0, 0);

  test('the first ping of a session always goes', () {
    expect(shouldSendPing(now: t0, lastSentAt: null), isTrue);
  });

  test('an excited double-tap is swallowed', () {
    expect(
      shouldSendPing(now: t0.add(const Duration(milliseconds: 120)), lastSentAt: t0),
      isFalse,
    );
  });

  test('the window is exactly the documented 3s, inclusive', () {
    expect(
      shouldSendPing(now: t0.add(const Duration(milliseconds: 2999)), lastSentAt: t0),
      isFalse,
    );
    expect(shouldSendPing(now: t0.add(pingDebounce), lastSentAt: t0), isTrue);
  });

  test('the flourish clears before the button comes back', () {
    // Otherwise the button snaps straight from "sent ♡" to available, and
    // the confirmation reads as a glitch rather than a beat.
    expect(pingSentFlourish, lessThan(pingDebounce));
  });

  test('a backwards clock jump does not lock the button', () {
    // NTP correction, timezone change mid-tap. Treated as "long enough ago"
    // rather than "wait for real time to catch up".
    expect(
      shouldSendPing(now: t0.subtract(const Duration(hours: 2)), lastSentAt: t0),
      isTrue,
    );
  });
}

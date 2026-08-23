/// How long the button stays shut after a ping goes out.
///
/// Three seconds is chosen to be *just* long enough to swallow a double-tap
/// or an excited mash, and short enough that deliberately sending a kiss
/// right after a hug still works. It's a courtesy to the person on the other
/// end (whose phone buzzes each time), not rate limiting — the server has no
/// opinion about how often you think about your person.
const pingDebounce = Duration(seconds: 3);

/// How long the "sent ♡" flourish stays up before the button goes back to
/// normal. Deliberately shorter than [pingDebounce] so the button spends a
/// beat visibly "resting" rather than snapping straight from confirmation to
/// available.
const pingSentFlourish = Duration(milliseconds: 1600);

/// Whether a ping sent at [now] is allowed, given the last one went out at
/// [lastSentAt] (null = none yet this session).
///
/// Pure so the rule is testable without a clock, a repository, or a widget.
bool shouldSendPing({required DateTime now, DateTime? lastSentAt}) {
  if (lastSentAt == null) return true;
  // A clock that jumped backwards (NTP correction, timezone change mid-tap)
  // would otherwise lock the button until real time caught up. Treat any
  // negative interval as "long enough ago".
  final since = now.difference(lastSentAt);
  return since.isNegative || since >= pingDebounce;
}

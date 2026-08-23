/// Pure, timezone-safe date-only day math for countdowns and the
/// anniversary "together" counter. Every comparison truncates to
/// year/month/day in local time so "today" means today's calendar date —
/// not "within the last 24 hours" — regardless of what time of day either
/// [DateTime] carries.
library;

import '../ui/core/strings/app_strings.dart';

const _monthAbbr = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Whole calendar days from [from]'s date to [to]'s date, ignoring
/// time-of-day — negative when [to]'s date is before [from]'s.
int daysBetweenDates(DateTime from, DateTime to) {
  final a = DateTime(from.year, from.month, from.day);
  final b = DateTime(to.year, to.month, to.day);
  return b.difference(a).inDays;
}

/// Days from [now] (defaults to [DateTime.now]) until [target]'s calendar
/// date. Positive = future, 0 = today, negative = already passed.
int daysUntil(DateTime target, {DateTime? now}) =>
    daysBetweenDates(now ?? DateTime.now(), target);

/// Friendly "in N days" / "today!! ✧" / "N days ago" label for a countdown
/// row — kb voice: warm, kaomoji accents.
String countdownDayLabel(int days) {
  if (days == 0) return AppStrings.countdownToday;
  if (days > 0) return AppStrings.countdownInDays(days);
  return AppStrings.countdownDaysAgo(-days);
}

/// Days together since [anniversary] — "together N days ♡". An anniversary
/// dated in the future (edge case: mistyped date) clamps to 0 rather than
/// showing a negative count.
int daysTogether(DateTime anniversary, {DateTime? now}) {
  final days = daysBetweenDates(anniversary, now ?? DateTime.now());
  return days < 0 ? 0 : days;
}

/// "24 Dec 2026" — local, friendly, no locale library needed for this one
/// format.
String friendlyDate(DateTime date) => '${date.day} ${_monthAbbr[date.month - 1]} ${date.year}';

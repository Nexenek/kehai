import '../strings/app_strings.dart';

/// Bare "Xm ago" phrase (no leading verb) — used wherever a caption needs
/// its own prefix, e.g. doodle captions ("from them · 5m ago").
String relativeTime(DateTime when) {
  final diff = DateTime.now().difference(when);
  if (diff.inSeconds < 45) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

/// Small "updated Xm ago" formatter — kept dependency-free rather than
/// pulling in intl for one string.
String timeAgo(DateTime when) {
  final relative = relativeTime(when);
  return relative == 'just now'
      ? AppStrings.updatedJustNow
      : 'updated $relative';
}

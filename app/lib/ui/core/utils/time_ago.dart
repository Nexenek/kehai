import '../strings/app_strings.dart';

/// Small "updated Xm ago" formatter — kept dependency-free rather than
/// pulling in intl for one string.
String timeAgo(DateTime when) {
  final diff = DateTime.now().difference(when);
  if (diff.inSeconds < 45) return AppStrings.updatedJustNow;
  if (diff.inMinutes < 60) return 'updated ${diff.inMinutes}m ago';
  if (diff.inHours < 24) return 'updated ${diff.inHours}h ago';
  return 'updated ${diff.inDays}d ago';
}

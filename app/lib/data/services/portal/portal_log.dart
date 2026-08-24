import 'package:flutter/foundation.dart';

/// Portal mode's diagnostic channel.
///
/// A portal call fails in the one place nothing else in this app does: out
/// in the network, between two machines, where neither side can see what
/// the other tried. When it goes wrong the only evidence is what the ICE
/// agent was doing at the time — so it gets printed, on both platforms, in
/// a form the user can copy out of `adb logcat -s flutter` or the desktop
/// terminal and send back.
///
/// Two levels, and the split is a privacy decision as much as a noise one:
///
///   * [portalLog] — always on, release included. State transitions and
///     failure summaries: a couple of dozen lines per call, no addresses.
///   * [portalTrace] — debug builds only. Per-candidate chatter, which is
///     high-volume and closer to the network topology of someone's home.
///
/// Neither ever prints a whole ICE candidate. A candidate line contains the
/// device's IP address on its local network (and, with a relay, the home
/// server's) — that's exactly the metadata this app exists to keep at home,
/// and it would end up pasted into a chat window the moment anybody debugs
/// anything. Type plus a short fingerprint says everything a diagnosis
/// needs: *which kind* of path was tried, and whether both ends are talking
/// about the same one.
const _prefix = '[KehaiPortal]';

void portalLog(String message) => debugPrint('$_prefix $message');

/// Debug-only detail. The closure defers building the string so a release
/// build doesn't pay for messages it will never print — which means it has
/// to be *called*, not interpolated. Interpolating it compiles perfectly
/// well and prints `Closure: () => String` — which is exactly what shipped
/// in the first diagnostics build, and what portal_log_test.dart now
/// guards against by capturing `debugPrint` and asserting on the text.
void portalTrace(String Function() message) {
  if (kDebugMode) debugPrint('$_prefix ${message()}');
}

/// The `typ` field out of an ICE candidate line, and nothing else.
///
/// A candidate looks like
/// `candidate:1 1 udp 2122260223 192.168.1.42 55555 typ host generation 0 …`
/// — everything before `typ` is an address we don't want in a log. Answers
/// `'?'` for an empty or unparseable candidate (the end-of-gathering
/// sentinel is an empty string, and it turns up often enough to be worth
/// not crashing on).
String portalCandidateType(String? candidate) {
  if (candidate == null || candidate.isEmpty) return 'end-of-candidates';
  final match = RegExp(r'\btyp\s+(\w+)').firstMatch(candidate);
  return match?.group(1) ?? '?';
}

/// A short, stable fingerprint of a candidate — enough to match "the one I
/// sent" against "the one they added" across two logs, revealing nothing
/// about the address it came from.
String portalCandidateFingerprint(String? candidate) {
  if (candidate == null || candidate.isEmpty) return '--------';
  return candidate.hashCode.toUnsigned(32).toRadixString(16).padLeft(8, '0');
}

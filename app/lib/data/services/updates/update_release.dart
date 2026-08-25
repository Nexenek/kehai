import 'dart:convert';

/// The pure half of "is there a newer Kehai?": parsing GitHub's
/// `releases/latest` JSON, comparing two version strings, and picking the
/// one asset this platform can actually install.
///
/// Not one line of this touches the network, the filesystem, or a clock —
/// which is the point. [UpdateService] is a state machine wrapped around
/// these three functions, and every interesting decision it makes is
/// testable here with a canned JSON string (see update_release_test.dart).

/// One downloadable file attached to a release.
class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
  });

  final String name;
  final String downloadUrl;

  /// Bytes, straight from the API — the only integrity check we do
  /// (see the spec's "Failure handling": size + archive integrity + the
  /// OS installer's own APK verification, no hash infrastructure).
  final int size;

  @override
  String toString() => 'ReleaseAsset($name, $size bytes)';
}

/// A published GitHub release, reduced to the four fields we care about.
class ReleaseInfo {
  const ReleaseInfo({
    required this.tag,
    required this.version,
    required this.notes,
    required this.assets,
  });

  /// As published, e.g. `v1.0.3`.
  final String tag;

  /// [tag] with any leading `v` stripped, e.g. `1.0.3`.
  final String version;

  /// The release body — shown nowhere yet, kept because it costs nothing
  /// and the chip may want a tooltip out of it one day.
  final String notes;

  final List<ReleaseAsset> assets;
}

/// Which platform's asset we're after. Kept as an enum rather than read
/// from `Platform` inside [selectAsset] so the selection rules can be
/// tested for all three from one desktop test run.
enum UpdateTarget { android, windows, linux }

/// Parses the body of `GET /repos/:owner/:repo/releases/latest`.
///
/// Returns null for anything that isn't a release object we can use — a
/// 404 body, a rate-limit message, truncated JSON. A check is best-effort
/// (spec: "any failure is logged state, never a dialog"), so "couldn't make
/// sense of it" and "couldn't reach it" deserve the same quiet handling.
ReleaseInfo? parseLatestRelease(String body) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } catch (_) {
    return null;
  }
  if (decoded is! Map<String, dynamic>) return null;

  final tag = decoded['tag_name'];
  if (tag is! String || tag.isEmpty) return null;
  final version = normalizeVersion(tag);
  if (version.isEmpty) return null;

  final assets = <ReleaseAsset>[];
  final rawAssets = decoded['assets'];
  if (rawAssets is List) {
    for (final raw in rawAssets) {
      if (raw is! Map<String, dynamic>) continue;
      final name = raw['name'];
      final url = raw['browser_download_url'];
      if (name is! String || url is! String) continue;
      final size = raw['size'];
      assets.add(
        ReleaseAsset(
          name: name,
          downloadUrl: url,
          size: size is int ? size : 0,
        ),
      );
    }
  }

  final notes = decoded['body'];
  return ReleaseInfo(
    tag: tag,
    version: version,
    notes: notes is String ? notes : '',
    assets: assets,
  );
}

/// `v1.0.3` → `1.0.3`, `1.0.3+7` → `1.0.3`, ` V1.0 ` → `1.0`.
///
/// The build number is deliberately dropped: it exists so Android's
/// versionCode can go up, and two builds of the same version are the same
/// release as far as an update is concerned.
String normalizeVersion(String raw) {
  var v = raw.trim();
  if (v.isNotEmpty && (v[0] == 'v' || v[0] == 'V')) v = v.substring(1);
  final plus = v.indexOf('+');
  if (plus >= 0) v = v.substring(0, plus);
  return v.trim();
}

/// Numeric triple compare: negative if [a] is older than [b], 0 if they're
/// the same release, positive if [a] is newer.
///
/// Missing components count as 0 (`1.1` == `1.1.0`) and non-numeric junk
/// counts as 0 too rather than throwing — a malformed tag should make the
/// app decide "not newer", never crash a background check.
int compareVersions(String a, String b) {
  final left = _parts(a);
  final right = _parts(b);
  final length = left.length > right.length ? left.length : right.length;
  for (var i = 0; i < length; i++) {
    final l = i < left.length ? left[i] : 0;
    final r = i < right.length ? right[i] : 0;
    if (l != r) return l < r ? -1 : 1;
  }
  return 0;
}

List<int> _parts(String version) =>
    normalizeVersion(version)
        .split('.')
        .map((part) => int.tryParse(part.trim()) ?? 0)
        .toList();

/// Whether [candidate] is a release worth offering to someone running
/// [current].
bool isNewerVersion(String candidate, String current) =>
    compareVersions(candidate, current) > 0;

/// The `name` rules the release assets already follow (spec's
/// "Release-side requirements: none"). Prefix + extension rather than an
/// exact name, because the desktop archives carry the version in the
/// middle: `kehai-windows-x64-1.0.3.zip`.
const _assetRules = {
  UpdateTarget.android: (prefix: 'kehai-release', suffix: '.apk'),
  UpdateTarget.windows: (prefix: 'kehai-windows-x64-', suffix: '.zip'),
  UpdateTarget.linux: (prefix: 'kehai-linux-x64-', suffix: '.tar.gz'),
};

/// The one asset [target] can install, or null if this release doesn't
/// carry one (a release that only shipped, say, the APK).
///
/// The android prefix is `kehai-release` rather than `kehai-` on purpose:
/// `kehai-debug.apk` also lives in the dist folder and must never be
/// offered as an update.
ReleaseAsset? selectAsset(List<ReleaseAsset> assets, UpdateTarget target) {
  final rule = _assetRules[target]!;
  for (final asset in assets) {
    final name = asset.name.toLowerCase();
    if (name.startsWith(rule.prefix) && name.endsWith(rule.suffix)) {
      return asset;
    }
  }
  return null;
}

/// The raw `{exe, title}` result of the `getForegroundApp` MethodChannel
/// call (windows/runner/presence_channel.cpp): `exe` is the foreground
/// process's image name, lowercased and without its `.exe` extension;
/// `title` is its window's text, which can legitimately be empty (some
/// windows have none) but is never null once a process was resolved at
/// all.
///
/// Deliberately not part of [DevicePresence]/the heartbeat yet — this is
/// just the native passthrough. The privacy opt-in and the
/// friendly-name/allowlist mapping layer that turns this into an
/// `activity` telemetry field land in a later pass.
typedef ForegroundApp = ({String exe, String title});

/// Pure mapping from the raw `getForegroundApp` channel result to
/// [ForegroundApp], kept separate from the channel I/O in
/// `WindowsPresenceService` so it can be unit-tested with hand-built maps
/// instead of a live platform channel — mirrors `WindowsPlayerMapper`.
class WindowsForegroundAppMapper {
  const WindowsForegroundAppMapper._();

  /// Maps one `getForegroundApp` result (`null`, or a
  /// `{exe, title}`-shaped map — values arrive as `Object?` since
  /// `MethodChannel` decodes a `StandardMethodCodec` map as
  /// `Map<Object?, Object?>`). Returns null for anything that isn't a
  /// well-formed map with a non-empty `exe`; a missing/non-string `title`
  /// is treated as an empty title rather than making the whole result null,
  /// since an untitled window is a normal case the native side already
  /// reports as `""`.
  static ForegroundApp? map(Object? raw) {
    if (raw is! Map) return null;
    final exe = raw['exe'] as String?;
    if (exe == null || exe.isEmpty) return null;
    final title = raw['title'] as String?;
    return (exe: exe, title: title ?? '');
  }
}

# Auto-updates — design

**Date:** 2026-08-25
**Status:** approved (design reviewed in conversation)

## Purpose

Kehai ships as a sideloaded APK, a Windows zip, and a Linux tar.gz on GitHub
Releases (`Nexenek/kehai`). Today an update means both users manually
downloading and reinstalling. This adds one-click in-app updates: the app
notices a newer release, offers it quietly, and — on one click — downloads,
verifies, and applies it.

Non-goals: store/package-manager distribution (winget, F-Droid, AppImage),
delta updates, silent background installs, snooze/skip-version machinery,
server-side involvement. Two users; keep it small.

## Architecture

One new service plus a small UI chip and a per-platform apply step.

```
UpdateService (Dart, ChangeNotifier)
  ├─ check:    GET api.github.com/repos/Nexenek/kehai/releases/latest
  ├─ compare:  tag vX.Y.Z  vs  package_info_plus current version
  ├─ download: platform asset → staging, verify byte size
  └─ apply:    Android → system installer (MethodChannel)
               Windows → detached .bat helper, swap + relaunch
               Linux   → detached .sh helper, swap + relaunch
```

### UpdateService

`app/lib/data/services/update_service.dart`, plain `ChangeNotifier` (house
style — no state-management framework).

- **Check source**: `GET https://api.github.com/repos/Nexenek/kehai/releases/latest`
  with a `User-Agent` header, unauthenticated. The endpoint excludes drafts
  and prereleases. Parsed fields: `tag_name`, `body` (notes), `assets[]`
  (`name`, `browser_download_url`, `size`).
- **Version compare**: strip `v`, numeric triple compare against the running
  version from `package_info_plus` (new dependency). Build number ignored.
  Debug/dev builds never update (guard on `kReleaseMode`).
- **Cadence**: one check after launch, deferred until the connectivity
  monitor reports online; then every 24 h while running. Manual
  "check for updates" entry in the desktop tray menu and Android settings.
  Checks are best-effort: any failure is logged state, never a dialog.
- **Asset selection by prefix** (release naming stays as-is):
  - Android: `kehai-release.apk`
  - Windows: `kehai-windows-x64-*.zip`
  - Linux: `kehai-linux-x64-*.tar.gz`
- **States**: `idle → checking → available(version) → downloading(progress)
  → readyToApply → applying`, `failed(reason)` reachable from any active
  state, retry re-runs the step that failed. One download at a time; a periodic
  check while one is in flight is a no-op.

### UI surface

Same philosophy as the offline badge: a status, not an alarm.

- A small chip above the partner card (sibling of the offline badge slot):
  soft dot + "v1.0.3 is here — tap to update". Tap starts the download; the
  chip becomes a one-line progress indicator, then applies. On failure:
  "update failed — tap to retry".
- Desktop tray menu gains "update to v1.0.3" while one is available.
- No snooze/skip. The chip is quiet enough to ignore.

## Per-platform apply

### Android

- Download to the app cache dir.
- A small MethodChannel in `MainActivity` (Kotlin, no new plugin) fires
  `ACTION_VIEW` with a `content://` URI (FileProvider) and MIME
  `application/vnd.android.package-archive`.
- Manifest additions: `REQUEST_INSTALL_PACKAGES` permission, FileProvider
  entry + `file_paths.xml` scoped to the cache dir.
- Releases are signed with the project keystore, so the installer updates in
  place with data intact. One OS confirm tap per update, plus a one-time
  "allow Kehai to install apps" system toggle. Debug-build installs still
  require a manual uninstall first (signature mismatch), unchanged.

### Windows

- Download zip to `%TEMP%`, extract with PowerShell `Expand-Archive` (no new
  Dart dependency), verify `couples_app.exe` exists in staging.
- Write a small `.bat` helper to temp; spawn detached; app exits. Helper:
  wait for our PID → mirror staged files over the install dir (the running
  exe's own directory, so any unzip location works) → relaunch the app →
  delete staging and itself.

### Linux

- Same shape with `tar -xzf` and a `.sh` helper.
- Target is the running bundle's directory (`Platform.resolvedExecutable`'s
  parent), so it covers both the `install.sh` layout (`~/.local/opt/kehai`)
  and a bundle run from anywhere. Desktop-entry `Exec` paths stay valid
  because the directory path does not change.
- Swap: `mv` current dir → `<dir>.old`, `mv` staging into place, relaunch.
  `<dir>.old` survives one cycle and is removed on the next healthy start —
  a bad update always leaves a working copy.

## Failure handling

- Download verified against the asset's `size` from the API; extraction
  failure catches corruption. No hash infrastructure (YAGNI — size check +
  archive integrity + the OS installer's own APK verification).
- The running installation is never touched until a fully verified staging
  dir exists; every failure lands in `failed(reason)` with the old version
  still running.
- Helper scripts are generated at update time with absolute paths; they are
  throwaway and self-deleting.

## Testing

- Unit tests (existing style, `fakeAsync` where timers are involved):
  version comparison, asset selection from canned API JSON, state-machine
  transitions with a fake HTTP layer, string-level tests of generated
  helper scripts (paths, PID wait, swap order).
- Manual per-platform pass using a version override (debug flag forcing the
  current version down) so a "newer" release can be simulated without
  publishing one.

## Release-side requirements

None. Current asset names already match the prefix rules; `releases/latest`
already skips drafts/prereleases.

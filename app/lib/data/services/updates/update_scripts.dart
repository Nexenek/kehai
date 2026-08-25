/// The two throwaway helper scripts that actually swap a desktop install.
///
/// A running program cannot replace its own files on Windows (the exe and
/// every loaded dll are locked) and would be replacing the code underneath
/// itself on Linux, so the last thing Kehai does is write one of these,
/// spawn it detached, and quit. The script waits for our PID to disappear,
/// puts the new build in place, starts it, and deletes itself.
///
/// Both are generated with absolute paths at update time — nothing here is
/// installed, nothing survives a failed update, and there is no second copy
/// to keep in sync. Kept as pure string builders so the interesting
/// properties (the PID wait comes before the swap; the relaunch comes after
/// it; every path is quoted) are assertable in a unit test with no processes
/// involved — see update_scripts_test.dart.
library;

/// Where a Linux install's safety copy lives while the new one proves
/// itself: the same directory with `.old` glued on, next to it rather than
/// inside it (so the swap is one atomic-ish `mv` of the whole tree, and so
/// the copy isn't inside the thing being replaced).
///
/// Removed on the next healthy start — see
/// [DesktopUpdateInstaller.cleanUpAfterUpdate].
String backupDirPath(String installDir) => '$installDir.old';

/// The Windows helper.
///
/// `robocopy` rather than `xcopy`/`copy`: it is the only thing in a stock
/// Windows that copies a tree over another tree without prompting, and its
/// "success" exit codes are the documented 0–7 (8 and up are real
/// failures). We copy *over* the install dir rather than mirroring it,
/// because `/MIR` would delete anything the user keeps alongside the app.
///
/// `ping` rather than `timeout` for the wait: `timeout` refuses to run when
/// stdin isn't a console, which is exactly the situation a detached helper
/// is in.
String windowsUpdateScript({
  required int pid,
  required String stagingDir,
  required String installDir,
  required String exePath,
}) =>
    '''
@echo off
rem Kehai updater — generated at update time, deletes itself on the way out.
setlocal
set "PID=$pid"
set "STAGING=$stagingDir"
set "INSTALL=$installDir"
set "EXE=$exePath"

rem 1. Wait for the app we're about to overwrite to actually be gone. Capped
rem    at ~60s: if it somehow never exits we bail out rather than copying
rem    over a live install.
set /a TRIES=0
:wait
tasklist /FI "PID eq %PID%" /NH 2>nul | find "%PID%" >nul
if errorlevel 1 goto swap
set /a TRIES+=1
if %TRIES% GEQ 60 goto done
ping -n 2 127.0.0.1 >nul
goto wait

rem 2. Put the new build in place. Exit codes 0-7 are robocopy's flavours of
rem    success; 8+ is a real failure, and then we do not relaunch a
rem    half-copied install.
:swap
robocopy "%STAGING%" "%INSTALL%" /E /NFL /NDL /NJH /NJS /NC /NS /NP >nul
if errorlevel 8 goto done

rem 3. Start the new one.
start "" "%EXE%"

rem 4. Tidy up after ourselves, the script file included.
:done
rmdir /s /q "%STAGING%"
del "%~f0"
''';

/// The Linux helper.
///
/// The swap is two renames rather than a copy, so the install directory is
/// never half-new: `dir` becomes `dir.old`, staging becomes `dir`. If the
/// second rename fails the first is undone, and the user is left running
/// exactly what they were running before.
///
/// `nohup ... &` rather than `setsid`: coreutils is a safer assumption than
/// util-linux, and either way the new process must not die with this
/// script's session.
String linuxUpdateScript({
  required int pid,
  required String stagingDir,
  required String installDir,
  required String exePath,
}) {
  final backup = backupDirPath(installDir);
  return '''
#!/usr/bin/env bash
# Kehai updater — generated at update time, deletes itself on the way out.
set -u
PID=$pid
STAGING="$stagingDir"
INSTALL="$installDir"
BACKUP="$backup"
EXE="$exePath"

# Never hold the directory we're about to move.
cd / || exit 1

# 1. Wait for the app we're about to replace to actually be gone. Capped at
#    ~60s, after which we give up rather than swapping under a live process.
for _ in \$(seq 1 300); do
  kill -0 "\$PID" 2>/dev/null || break
  sleep 0.2
done
if kill -0 "\$PID" 2>/dev/null; then
  rm -rf "\$STAGING"
  rm -f "\$0"
  exit 1
fi

# 2. Swap. The old install survives as \$BACKUP until the next healthy start,
#    so a bad update always leaves a working copy one `mv` away.
rm -rf "\$BACKUP"
mv "\$INSTALL" "\$BACKUP" || { rm -rf "\$STAGING"; rm -f "\$0"; exit 1; }
if ! mv "\$STAGING" "\$INSTALL"; then
  # Put the working copy back and change nothing else.
  mv "\$BACKUP" "\$INSTALL"
  rm -rf "\$STAGING"
  rm -f "\$0"
  exit 1
fi

# 3. Start the new one, detached from this script's session.
nohup "\$EXE" >/dev/null 2>&1 &

# 4. Tidy up after ourselves, the script file included.
rm -f "\$0"
''';
}

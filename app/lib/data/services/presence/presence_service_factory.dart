import 'dart:io';

import 'android/android_presence_service.dart';
import 'linux_presence_service.dart';
import 'presence_service.dart';
import 'stub_presence_service.dart';
import 'windows_presence_service.dart';

/// Picks the right [PresenceService] for the current platform. Linux gets
/// the MPRIS/idle implementation, Android the battery/screen/media-session
/// one, Windows the GSMTC/GetLastInputInfo one; everything else gets
/// [StubPresenceService].
PresenceService createPresenceService() {
  if (Platform.isLinux) return LinuxPresenceService();
  if (Platform.isAndroid) return AndroidPresenceService();
  if (Platform.isWindows) return WindowsPresenceService();
  return const StubPresenceService();
}

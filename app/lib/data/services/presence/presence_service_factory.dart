import 'dart:io';

import 'android/android_presence_service.dart';
import 'linux_presence_service.dart';
import 'presence_service.dart';
import 'stub_presence_service.dart';

/// Picks the right [PresenceService] for the current platform. Linux gets
/// the MPRIS/idle implementation, Android the battery/screen/media-session
/// one; everything else (Windows, for now) gets [StubPresenceService]
/// until its platform-specific signals land (see its doc comment for the
/// remaining phase2b plan).
PresenceService createPresenceService() {
  if (Platform.isLinux) return LinuxPresenceService();
  if (Platform.isAndroid) return AndroidPresenceService();
  return const StubPresenceService();
}

import 'dart:io';

import 'linux_presence_service.dart';
import 'presence_service.dart';
import 'stub_presence_service.dart';

/// Picks the right [PresenceService] for the current platform. Linux gets
/// the real MPRIS/idle implementation; everything else gets
/// [StubPresenceService] until its platform-specific signals land (see its
/// doc comment for the phase2b plan).
PresenceService createPresenceService() {
  if (Platform.isLinux) return LinuxPresenceService();
  return const StubPresenceService();
}

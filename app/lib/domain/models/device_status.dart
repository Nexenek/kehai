import 'package:flutter/foundation.dart';

/// A `devices` record — used to light up the phone/desktop glyphs on the
/// partner card. "Online" = last_seen within the last 2 minutes (heartbeat
/// interval is 30s, so a 2-minute window tolerates a few missed beats).
@immutable
class DeviceStatus {
  const DeviceStatus({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.kind,
    required this.lastSeen,
  });

  final String id;
  final String ownerId;
  final String name;
  final String kind; // phone | desktop | tablet | portal
  final DateTime lastSeen;

  static const onlineWindow = Duration(minutes: 2);

  bool get isOnline => DateTime.now().toUtc().difference(lastSeen.toUtc()) <= onlineWindow;
}

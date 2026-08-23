import 'package:flutter/foundation.dart';

import '../../../domain/models/ambient_line.dart';
import '../../../domain/models/device_status.dart';
import '../../../domain/models/mood.dart';
import '../../../domain/models/partner_status.dart';
import '../../../ui/core/strings/app_strings.dart';

/// The two strings the ongoing notification renders: a title line and a
/// body that Android shows with `BigTextStyle`, so `\n`s survive when the
/// notification is expanded and collapse to one line when it isn't.
@immutable
class PartnerNotificationContent {
  const PartnerNotificationContent({required this.title, required this.text});

  final String title;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is PartnerNotificationContent &&
      other.title == title &&
      other.text == text;

  @override
  int get hashCode => Object.hash(title, text);

  @override
  String toString() => 'PartnerNotificationContent("$title", "$text")';
}

/// Builds the ongoing notification's copy — the pocket-sized version of
/// design-language.md's signature "partner window": partner name, mood
/// kaomoji, their note, the ambient line, and the device-source
/// indicator.
///
/// This is the *only* place those strings get composed. The Kotlin side
/// renders whatever it's handed and knows nothing about moods, precedence
/// or device glyphs — the background Dart isolate pushes finished strings
/// down via `FlutterForegroundTask.updateService`, so [resolveAmbientLine]
/// stays a single implementation shared with the partner card instead of
/// being ported (and then quietly diverging) in Kotlin.
///
/// Pure and clock-free apart from [DeviceStatus.isOnline], so it unit
/// tests with hand-built records.
PartnerNotificationContent buildPartnerNotification({
  required String? partnerName,
  required PartnerStatus? status,
  required List<DeviceStatus> partnerDevices,
}) {
  if (partnerName == null || partnerName.isEmpty) {
    return const PartnerNotificationContent(
      title: AppStrings.notificationWaitingTitle,
      text: AppStrings.notificationWaitingText,
    );
  }

  final mood = status == null ? null : MoodCatalog.byId(status.moodId);
  final title = mood == null
      ? partnerName
      : '$partnerName  ${mood.kaomoji}';

  final lines = <String>[];

  final note = status?.note.trim() ?? '';
  if (note.isNotEmpty) lines.add(note);

  final ambient = resolveAmbientLine(partnerDevices);
  if (ambient != null) lines.add(ambient.text);

  lines.add(_deviceLine(partnerDevices));

  return PartnerNotificationContent(title: title, text: lines.join('\n'));
}

/// The notification's stand-in for the partner card's lit/dim 📱/🖥 pixel
/// glyphs. Only lit devices are named — a dim glyph reads fine in a
/// window with two fixed slots, but in a notification an unlit label is
/// just a lie you have to squint at.
String _deviceLine(List<DeviceStatus> devices) {
  final phone = devices.any((d) => d.kind == 'phone' && d.isOnline);
  final desktop = devices.any((d) => d.kind == 'desktop' && d.isOnline);
  if (phone && desktop) return AppStrings.notificationDevicesBoth;
  if (phone) return AppStrings.notificationDevicesPhone;
  if (desktop) return AppStrings.notificationDevicesDesktop;
  return AppStrings.notificationDevicesNone;
}

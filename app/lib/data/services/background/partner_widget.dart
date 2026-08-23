import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../../../domain/models/ambient_line.dart';
import '../../../domain/models/device_status.dart';
import '../../../domain/models/mood.dart';
import '../../../domain/models/partner_status.dart';
import '../../../ui/core/strings/app_strings.dart';

/// The SharedPreferences keys the Glance widget
/// (`app.kehai.widget.PartnerWidgetAppWidget`) reads directly via
/// `HomeWidgetGlanceStateDefinition`. Keep these in sync with
/// `android/app/src/main/kotlin/app/kehai/widget/PartnerWidget.kt` — they
/// are the entire contract between the two sides.
class PartnerWidgetKeys {
  const PartnerWidgetKeys._();

  static const partnerName = 'partner_name';
  static const moodKaomoji = 'mood_kaomoji';
  static const ambientLine = 'ambient_line';
  static const updatedEpochMs = 'updated_epoch_ms';
}

/// `qualifiedAndroidName` for [HomeWidget.updateWidget] — must match the
/// receiver declared in AndroidManifest.xml.
const String partnerWidgetReceiver = 'app.kehai.widget.PartnerWidgetReceiver';

/// The four values the home-screen widget renders: partner name, mood
/// kaomoji (large), ambient line, and the epoch millis the widget derives
/// "updated Xm ago" from in Kotlin.
///
/// A null [partnerName] is the empty state ("waiting for them ( . .)") —
/// the widget shows that whenever the key is absent, same convention as
/// [PartnerWidgetKeys].
@immutable
class PartnerWidgetData {
  const PartnerWidgetData({
    this.partnerName,
    this.moodKaomoji,
    this.ambientLine,
    this.updatedEpochMs,
  });

  final String? partnerName;
  final String? moodKaomoji;
  final String? ambientLine;
  final int? updatedEpochMs;

  @override
  bool operator ==(Object other) =>
      other is PartnerWidgetData &&
      other.partnerName == partnerName &&
      other.moodKaomoji == moodKaomoji &&
      other.ambientLine == ambientLine &&
      other.updatedEpochMs == updatedEpochMs;

  @override
  int get hashCode =>
      Object.hash(partnerName, moodKaomoji, ambientLine, updatedEpochMs);

  @override
  String toString() =>
      'PartnerWidgetData(partnerName: $partnerName, moodKaomoji: '
      '$moodKaomoji, ambientLine: $ambientLine, updatedEpochMs: '
      '$updatedEpochMs)';
}

/// Maps partner status → the widget's key/value contract. Pure and
/// clock-free (unlike the notification's "just now" precedence, the
/// widget's "updated Xm ago" is rendered from the epoch on the Kotlin
/// side, so this needs no clock of its own — same [status]-in,
/// same-[PartnerWidgetData]-out on every call), so it unit tests with
/// hand-built records exactly like [buildPartnerNotification].
///
/// "Updated" mirrors the partner card's own `timeAgo(status.updated)` —
/// it's the mood/note timestamp, not device freshness — so the widget and
/// the in-app card never disagree about what "updated" means.
PartnerWidgetData buildPartnerWidgetData({
  required String? partnerName,
  required PartnerStatus? status,
  required List<DeviceStatus> partnerDevices,
}) {
  if (partnerName == null || partnerName.isEmpty) {
    return const PartnerWidgetData();
  }

  final mood = status == null ? null : MoodCatalog.byId(status.moodId);
  final ambient = resolveAmbientLine(partnerDevices);

  return PartnerWidgetData(
    partnerName: partnerName,
    moodKaomoji: mood?.kaomoji,
    ambientLine: ambient?.text ?? AppStrings.ambientAway,
    updatedEpochMs: status?.updated.millisecondsSinceEpoch,
  );
}

/// Persists [buildPartnerWidgetData]'s output via `home_widget` and asks
/// Android to redraw the widget. Best-effort and silent on failure: this
/// runs from both the background isolate and the UI isolate on every
/// partner update, and a missing widget host (desktop builds, no widget
/// pinned yet) or a transient platform-channel error must never break the
/// caller's own render/notification path.
Future<void> updatePartnerWidget({
  required String? partnerName,
  required PartnerStatus? status,
  required List<DeviceStatus> partnerDevices,
}) async {
  final data = buildPartnerWidgetData(
    partnerName: partnerName,
    status: status,
    partnerDevices: partnerDevices,
  );
  try {
    await HomeWidget.saveWidgetData<String>(
      PartnerWidgetKeys.partnerName,
      data.partnerName,
    );
    await HomeWidget.saveWidgetData<String>(
      PartnerWidgetKeys.moodKaomoji,
      data.moodKaomoji,
    );
    await HomeWidget.saveWidgetData<String>(
      PartnerWidgetKeys.ambientLine,
      data.ambientLine,
    );
    await HomeWidget.saveWidgetData<int>(
      PartnerWidgetKeys.updatedEpochMs,
      data.updatedEpochMs,
    );
    await HomeWidget.updateWidget(qualifiedAndroidName: partnerWidgetReceiver);
  } catch (_) {
    // No widget host on this platform, or the channel isn't there yet —
    // fine, the next successful render will catch the widget up.
  }
}

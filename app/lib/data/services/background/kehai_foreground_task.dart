import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';

import '../../../ui/core/strings/app_strings.dart';
import 'kehai_task_handler.dart';
import 'partner_notification.dart';

/// Wrapper around `flutter_foreground_task` — the one place that knows the
/// service's channel, id, foreground-service type and notification
/// defaults. Every member is a no-op / "false" off Android so callers can
/// stay platform-agnostic.
///
/// ## Why a foreground service at all
///
/// kb/platform-android.md, "24/7 background operation": a foreground
/// service with a persistent notification "is what we WANT anyway — it's
/// the status notification". The service keeps a second Flutter engine (a
/// background Dart isolate, see [KehaiTaskHandler]) alive, which owns the
/// heartbeat, the presence sources and the partner realtime subscription
/// while the app is backgrounded.
///
/// ## Why `specialUse` and not `dataSync`
///
/// Android 14+ makes `android:foregroundServiceType` mandatory. Of the two
/// candidates:
///
/// - `dataSync` describes bounded transfer work (upload/download/backup),
///   and Android 15 caps it at **6 hours per 24** for apps targeting 35+,
///   after which the system stops the service. A companion-presence app
///   that goes dark every afternoon is a broken companion-presence app.
/// - `specialUse` is explicitly "any valid foreground service use case not
///   covered by the other types", has **no runtime prerequisites and no
///   timeout**, and only requires a manifest `<property>` declaring the
///   subtype (`android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE`, see
///   AndroidManifest.xml). Its one cost is that Google Play reviews the
///   stated subtype — irrelevant here, since Kehai is sideloaded /
///   F-Droid-distributed (kb/platform-android.md).
///
/// `specialUse` also isn't on Android 15's list of types forbidden from
/// starting out of a `BOOT_COMPLETED` receiver (dataSync is), which is
/// what makes `autoRunOnBoot` below actually work.
///
/// So: `specialUse`, subtype documented in the manifest property.
class KehaiForegroundTask {
  const KehaiForegroundTask._();

  /// Only Android has the service. Desktop keeps heartbeating from the UI
  /// isolate exactly as it did in phase 2a.
  static bool get isSupported => Platform.isAndroid;

  /// Arbitrary but stable: the notification id doubles as the service id,
  /// and keeping it fixed means an update replaces the pinned
  /// notification instead of stacking a second one.
  static const serviceId = 1091;

  static const _channelId = 'kehai_partner_window';

  static var _configured = false;

  /// Called once from `main()`. [FlutterForegroundTask.initCommunicationPort]
  /// registers the port the service's isolate uses to talk back to the UI
  /// isolate, and has to happen before any service can start.
  static void bootstrap() {
    if (!isSupported) return;
    FlutterForegroundTask.initCommunicationPort();
    configure();
  }

  /// Registers channel + task options. Safe to call repeatedly, and must
  /// be called before [start] in whichever isolate calls it.
  static void configure() {
    if (!isSupported || _configured) return;
    _configured = true;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _channelId,
        channelName: AppStrings.notificationChannelName,
        channelDescription: AppStrings.notificationChannelDescription,
        // LOW + no sound/vibration + alert-once: this notification is
        // furniture, not an interruption. design-language.md's voice is
        // "soft, safe and warm"; a companion window that buzzes every time
        // your partner skips a track is neither.
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        enableVibration: false,
        playSound: false,
        showWhen: false,
        showBadge: false,
        onlyAlertOnce: true,
        visibility: NotificationVisibility.VISIBILITY_PRIVATE,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // The isolate does its real work from realtime subscriptions and
        // its own 30s heartbeat timer; this repeat only re-renders the
        // notification so relative state ("away", device glyphs going
        // dark) doesn't rot between partner events.
        eventAction: ForegroundTaskEventAction.repeat(60 * 1000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
        // Survive the app being swiped out of recents — that's precisely
        // the case this whole feature exists for.
        stopWithTask: false,
      ),
    );
  }

  static Future<bool> get isRunning async {
    if (!isSupported) return false;
    try {
      return await FlutterForegroundTask.isRunningService;
    } catch (_) {
      return false;
    }
  }

  /// Starts the service (and with it the background isolate). Returns
  /// false if Android refused — a denied notification permission, an OEM
  /// restriction, a background-start block — in which case the caller
  /// should keep heartbeating from the UI isolate instead.
  static Future<bool> start() async {
    if (!isSupported) return false;
    configure();
    try {
      if (await FlutterForegroundTask.isRunningService) return true;
      final result = await FlutterForegroundTask.startService(
        serviceId: serviceId,
        // `location` is declared alongside `specialUse` in the manifest
        // (`specialUse|location`) so LocationPublisher's background fixes
        // are allowed while the service is up — but Android 14+ throws a
        // SecurityException if a foreground service *starts* claiming the
        // `location` type without ACCESS_COARSE/FINE_LOCATION already
        // granted, so it's only requested here when that's already true.
        // Most installs never grant it (shareLocation defaults off), which
        // is exactly the case this guards.
        //
        // ON-DEVICE VERIFICATION NEEDED: if location permission is granted
        // *after* this service is already running, the running instance
        // keeps its original type set until restarted — the superpowers
        // screen's "stop"/"start" service row is the manual workaround;
        // confirm on a real device whether that's needed in practice or
        // whether geolocator calls still succeed regardless.
        serviceTypes: [
          ForegroundServiceTypes.specialUse,
          if (await _hasLocationPermission) ForegroundServiceTypes.location,
        ],
        notificationTitle: AppStrings.notificationStartingTitle,
        notificationText: AppStrings.notificationStartingText,
        // The default/fallback glyph — see `render`'s doc comment on why
        // this is a manifest meta-data name rather than a raw resource id.
        // Set explicitly so the very first notification (before any
        // partner data has arrived to drive [render]'s icon choice) uses
        // Kehai's dedicated status-bar icon set rather than falling back to
        // the full-color launcher mipmap.
        notificationIcon: const NotificationIcon(metaDataName: 'ic_stat_heart'),
        notificationInitialRoute: '/',
        callback: kehaiTaskCallback,
      );
      return result is ServiceRequestSuccess;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> get _hasLocationPermission async {
    try {
      final permission = await Geolocator.checkPermission();
      return permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }

  static Future<void> stop() async {
    if (!isSupported) return;
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (_) {
      // Already gone / never started — nothing to clean up.
    }
  }

  /// Pushes a one-shot "go re-read your sharing prefs" signal to the
  /// background isolate via `sendDataToTask` — the instant path
  /// `KehaiTaskHandler.onReceiveData`/`_applySharingPrefs` use so a toggle
  /// flipped from the superpowers screen or the desktop sharing-settings
  /// dialog (`shareLocation`, `shareFocusedApp`, `shareUnknownApps`) takes
  /// effect right away instead of waiting for the next 60s
  /// `onRepeatEvent` tick. The payload's content is never read on the other
  /// end — only its arrival matters — so any constant works.
  ///
  /// Swallowed on failure like every other call here: the service may not
  /// be running yet (nothing to notify — its next start reads fresh prefs
  /// anyway) or the communication port may not be wired up in this
  /// process. Either way the existing 60s tick is the fallback that always
  /// catches up.
  static void notifyPrefsChanged() {
    if (!isSupported) return;
    try {
      FlutterForegroundTask.sendDataToTask('prefs_changed');
    } catch (_) {
      // No running service / no communication port yet — the next
      // onRepeatEvent tick (or the next service start) catches this up.
    }
  }

  /// Payload prefix for the app-foreground push below. Kept as a prefix (not
  /// a bare constant) so [KehaiTaskHandler.onReceiveData] can tell it apart
  /// from the prefs nudge above with a `startsWith`.
  static const foregroundSignalPrefix = 'app_foreground:';

  /// Tells the background isolate whether the app is currently on screen.
  ///
  /// It needs to know because it — not the UI isolate — is what raises
  /// notifications on Android once the service is up, and a notification
  /// about a doodle you're watching arrive is noise ([decideNotification]'s
  /// rule 2). The service has no window to observe, so this is the only way
  /// it can find out.
  ///
  /// Swallowed on failure like [notifyPrefsChanged]: the worst case is a
  /// notification you didn't strictly need, which is the right direction to
  /// fail in.
  static void notifyAppForeground(bool foreground) {
    if (!isSupported) return;
    try {
      FlutterForegroundTask.sendDataToTask(
        '$foregroundSignalPrefix${foreground ? '1' : '0'}',
      );
    } catch (_) {
      // No running service / no communication port yet.
    }
  }

  /// Pushes finished strings (and, optionally, a new status-bar icon) into
  /// the notification. Called from the background isolate; the Kotlin side
  /// just renders them.
  ///
  /// [iconKey] is one of `notification_icon.dart`'s
  /// `notificationIconNames` (e.g. `ic_stat_music`), or `null` to leave the
  /// icon exactly as it is. Passing `null` isn't a "reset to default" —
  /// verified by reading `NotificationContent.updateData`/`update()` on the
  /// Kotlin side (`android/.../models/NotificationContent.kt`,
  /// `ForegroundServiceManager.update`): an update is a *merge* keyed on
  /// non-null fields, so an omitted icon leaves whatever the last real
  /// value was untouched instead of falling back to the app icon. That's
  /// what makes the caller's "only pass this when the icon key actually
  /// changed" dedup (`KehaiTaskHandler._render`) safe: skipping the icon on
  /// an unrelated text-only update (a new mood note, say) can't
  /// accidentally blank it.
  ///
  /// [NotificationIcon.metaDataName] is a manifest meta-data *key*, not a
  /// raw resource id/name flutter_foreground_task resolves at runtime —
  /// confirmed by reading `ForegroundService.getIconResId`, which does
  /// `applicationInfo.metaData.getInt(icon.metaDataName)`. So every value
  /// [iconKey] can take must have a matching
  /// `<meta-data android:resource="@drawable/...">` entry under
  /// `<application>` in AndroidManifest.xml (see the block there) — a
  /// name with no manifest entry resolves to icon id 0, which
  /// `Notification.Builder.setSmallIcon`/`NotificationCompat.Builder`
  /// silently treats as "no icon" rather than crashing, so a drift between
  /// this set and the manifest degrades gracefully instead of taking the
  /// service down. `notification_icon.dart`'s `notificationIconFor` only
  /// ever returns names from its own `notificationIconNames` set (asserted
  /// internally), which is kept in lockstep with the manifest entries and
  /// `tool/generate_notification_icons.py`'s `ICONS` map by hand.
  static Future<void> render(
    PartnerNotificationContent content, {
    String? iconKey,
  }) async {
    if (!isSupported) return;
    try {
      await FlutterForegroundTask.updateService(
        notificationTitle: content.title,
        notificationText: content.text,
        notificationIcon: iconKey == null
            ? null
            : NotificationIcon(metaDataName: iconKey),
      );
    } catch (_) {
      // Service stopped underneath us — the next start rebuilds it.
    }
  }

  // --- permission helpers, all "ask politely once, never block" ---

  static Future<bool> get hasNotificationPermission async {
    if (!isSupported) return false;
    try {
      final permission =
          await FlutterForegroundTask.checkNotificationPermission();
      return permission == NotificationPermission.granted;
    } catch (_) {
      return false;
    }
  }

  /// Android 13+ runtime `POST_NOTIFICATIONS` prompt. On 12 and below the
  /// platform reports granted without showing anything.
  static Future<bool> requestNotificationPermission() async {
    if (!isSupported) return false;
    try {
      final permission =
          await FlutterForegroundTask.requestNotificationPermission();
      return permission == NotificationPermission.granted;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> get isIgnoringBatteryOptimizations async {
    if (!isSupported) return false;
    try {
      return await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    } catch (_) {
      return false;
    }
  }

  /// Fires `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` — the one-tap
  /// system dialog. Only ever triggered from the explainer screen, never
  /// unprompted (kb/platform-android.md: "request battery-optimization
  /// exemption with a friendly explainer").
  static Future<bool> requestBatteryExemption() async {
    if (!isSupported) return false;
    try {
      return await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    } catch (_) {
      return false;
    }
  }
}

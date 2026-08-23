import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../ui/core/strings/app_strings.dart';
import '../prefs_service.dart';
import 'kehai_sound.dart';
import 'kehai_sound_player.dart';
import 'notification_decision.dart';

/// Raises Kehai's local notifications, and owns everything platform-shaped
/// about them: Android channels, desktop toasts, and which sound goes with
/// which event.
///
/// **Client-side only** (kb/roadmap.md's locked scope for this wave): there is
/// no push service anywhere in here. Every notification this class raises was
/// decided by *this* device, from a realtime event *this* device's own
/// long-running process received — the desktop app's UI isolate, or Android's
/// foreground-service isolate ([KehaiTaskHandler]). That's why a self-hosted
/// couples app can have notifications at all without an FCM/APNs round trip
/// through anybody else's servers.
///
/// ## Per-platform behaviour
///
/// | | notification | sound |
/// |---|---|---|
/// | Android | `NotificationChannel` per event type | the channel's — our `res/raw` WAV |
/// | Windows | WinRT toast, explicitly silent | we play it (winmm `PlaySound`) |
/// | Linux | D-Bus toast, `suppressSound: true` | we play it (`paplay`/`aplay`/…) |
///
/// The split is forced, not chosen: Android will only ever play a channel's
/// sound, and neither desktop toast API can carry an arbitrary local file
/// (Windows needs an MSIX package identity; the Linux `sound-file` hint is an
/// optional server capability most daemons ignore). See [KehaiSoundPlayer].
///
/// ## The Android channel-per-sound trick
///
/// A `NotificationChannel`'s sound is **immutable after creation** — Android
/// deliberately refuses to let an app change how loudly it can interrupt you
/// once you've seen the channel. So "pick a sound" can't edit a channel; it
/// has to mint a new one. Channel ids therefore carry the sound in them
/// (`kehai_evt_ping_sparkle`), and [_ensureChannel] deletes the event's other
/// channels as it goes, so the app's notification settings never grow a
/// graveyard of every sound you ever tried.
///
/// ## Do Not Disturb
///
/// Not fought anywhere. Android routes our channels through DND itself (we
/// never set `channelBypassDnd`), and on desktop the notification daemon /
/// Focus Assist decides. We deliberately do NOT probe for DND to skip the
/// sound ourselves: on Linux there's no portable way to ask, and on Windows
/// the query needs a WinRT call we'd rather not own — and both platforms
/// already suppress *their* sound during DND, while ours is the one the user
/// explicitly chose. If this proves wrong in daily use, the honest fix is a
/// "quiet hours" preference of our own rather than guessing at the OS's.
class KehaiNotifier implements NotificationSink {
  KehaiNotifier({
    required PrefsService prefs,
    @visibleForTesting FlutterLocalNotificationsPlugin? plugin,
    @visibleForTesting KehaiSoundPlayer? soundPlayer,
    @visibleForTesting bool? supportedOverride,
  }) : _prefs = prefs,
       _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       _soundPlayer = soundPlayer ?? KehaiSoundPlayer(),
       _supported = supportedOverride ?? isSupported;

  final PrefsService _prefs;
  final FlutterLocalNotificationsPlugin _plugin;
  final KehaiSoundPlayer _soundPlayer;
  final bool _supported;

  /// Notification ids. Stable per event type on purpose: a second ping
  /// replaces the first rather than stacking, so walking back to your desk
  /// finds "they're thinking of you", not a pile of eleven identical rows.
  static const int _idBase = 2100;
  static const int _previewId = 2199;

  /// A fixed GUID identifying Kehai's toast activation callback on Windows.
  /// Must never change once shipped — Windows keys the app's notification
  /// registration off it.
  static const _windowsGuid = 'a1c4f7d2-6b53-4e88-9f0a-2d7e5c1b3846';

  bool _initialized = false;

  /// The channel id currently live for each event kind, so [_ensureChannel]
  /// knows what to tear down when the sound changes.
  final Map<KehaiEventKind, String> _liveChannels = {};

  static bool get isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isLinux || Platform.isWindows);

  /// Idempotent. Safe to call from either isolate — the plugin instance is
  /// per-isolate, and so is this object.
  Future<void> initialize() async {
    if (!_supported || _initialized) return;
    _initialized = true;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          // The launcher icon doubles as the notification icon. A dedicated
          // monochrome status icon would be better on Android (the system
          // silhouettes whatever it's given); noted for the art pass.
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          linux: LinuxInitializationSettings(
            defaultActionName: AppStrings.notifyOpenAction,
            // We always play our own sound (see the class doc), so tell the
            // daemon not to add one of its own on top.
            defaultSuppressSound: true,
          ),
          windows: WindowsInitializationSettings(
            appName: AppStrings.appName,
            appUserModelId: 'Nexenek.Kehai.Companion',
            guid: _windowsGuid,
          ),
        ),
      );
      if (Platform.isAndroid) {
        for (final kind in KehaiEventKind.values) {
          await _ensureChannel(kind, soundFor(kind));
        }
      }
    } catch (error) {
      // A denied POST_NOTIFICATIONS, a desktop with no notification daemon,
      // a Windows registration that wouldn't take — none of these are worth
      // a crash. Notifications are a courtesy; the app works without them.
      debugPrint('notifications unavailable: $error');
    }
  }

  /// The sound currently chosen for [kind] — the persisted value, or the
  /// event's own default (ping = sparkle, doodle = pop, instant/reveal =
  /// chime).
  KehaiSound soundFor(KehaiEventKind kind) => KehaiSound.byId(
    _prefs.notificationSound(kind.id),
    fallback: kind.defaultSound,
  );

  /// Persists a new choice and, on Android, mints the replacement channel
  /// immediately so the very next notification is already using it.
  Future<void> setSound(KehaiEventKind kind, KehaiSound sound) async {
    await _prefs.setNotificationSound(kind.id, sound.id);
    if (_supported && Platform.isAndroid) {
      await _ensureChannel(kind, sound);
    }
  }

  /// Re-reads the persisted sounds from disk and re-applies them. The
  /// background isolate calls this: SharedPreferences caches per isolate, so
  /// a sound picked in the app is invisible here until we reload (the exact
  /// shape of the `shareLocation` staleness bug documented in
  /// [KehaiTaskHandler._applySharingPrefs]).
  Future<void> refreshFromPrefs() async {
    if (!_supported) return;
    await _prefs.reload();
    if (!Platform.isAndroid) return;
    for (final kind in KehaiEventKind.values) {
      await _ensureChannel(kind, soundFor(kind));
    }
  }

  /// Raises [request]. Callers get here through [decideNotification], which
  /// has already applied the self-echo and foreground rules — this method
  /// asks no questions.
  @override
  Future<void> notify(NotificationRequest request) async {
    if (!_supported) return;
    await initialize();
    final sound = soundFor(request.eventKind);
    try {
      await _plugin.show(
        id: _idBase + request.eventKind.index,
        title: request.title,
        body: request.body,
        notificationDetails: await _detailsFor(request.eventKind, sound),
        payload: request.eventKind.id,
      );
    } catch (error) {
      debugPrint('notification not shown: $error');
    }
    // Desktop only — on Android the channel already carried the sound, and
    // KehaiSoundPlayer is a no-op there anyway.
    await _soundPlayer.play(sound);
  }

  /// Whether a chosen sound will actually be heard on this machine.
  ///
  /// Always true on Android (the channel is the player). On desktop it
  /// depends on [KehaiSoundPlayer] finding something to play with — a Linux
  /// box with no `paplay`/`aplay`/`ffplay` can show notifications but not
  /// sound them, and the picker says so rather than pretending.
  Future<bool> get soundsAudible async {
    if (!_supported) return false;
    if (Platform.isAndroid) return true;
    return _soundPlayer.isAudible;
  }

  /// Plays [sound] the way [kind] would, for the settings picker's
  /// preview-on-tap.
  ///
  /// On desktop that's just the file. On Android it can't be: the *only*
  /// thing that plays a channel sound is a notification on that channel, so
  /// the preview posts a real one and pulls it back down again a moment
  /// later. That turns out to be the more honest preview anyway — what you
  /// hear is exactly what a real ping will sound like, at the volume Android
  /// has decided that channel gets.
  Future<void> preview(KehaiEventKind kind, KehaiSound sound) async {
    if (!_supported || sound.isSilent) return;
    await initialize();
    if (!Platform.isAndroid) {
      await _soundPlayer.play(sound);
      return;
    }
    try {
      await _ensureChannel(kind, sound);
      await _plugin.show(
        id: _previewId,
        title: AppStrings.soundsPreviewTitle,
        body: AppStrings.soundsPreviewBody(sound.label),
        notificationDetails: await _detailsFor(kind, sound),
      );
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      await _plugin.cancel(id: _previewId);
    } catch (error) {
      debugPrint('sound preview failed: $error');
    }
  }

  Future<NotificationDetails> _detailsFor(
    KehaiEventKind kind,
    KehaiSound sound,
  ) async {
    if (Platform.isAndroid) {
      final channelId = await _ensureChannel(kind, sound);
      return NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          AppStrings.notifyChannelName(kind),
          channelDescription: AppStrings.notifyChannelDescription(kind),
          importance: Importance.high,
          priority: Priority.high,
          playSound: !sound.isSilent,
          sound: sound.isSilent
              ? null
              : RawResourceAndroidNotificationSound(sound.androidResource),
          // Vibration follows the sound: "silent" should mean silent, not
          // "silent but still buzzing in your pocket".
          enableVibration: !sound.isSilent,
          autoCancel: true,
          // Private: the lock screen shows that Kehai has something to say
          // without putting "sent you a kiss" on a screen anyone can see.
          visibility: NotificationVisibility.private,
        ),
      );
    }
    return const NotificationDetails(
      // Both desktop toasts are explicitly silent — we play the chosen sound
      // ourselves right after (see the class doc).
      linux: LinuxNotificationDetails(suppressSound: true),
      windows: WindowsNotificationDetails(),
    );
  }

  /// Creates (or re-uses) the channel for [kind]+[sound] and retires the
  /// event's previous one. Returns the channel id to post on.
  Future<String> _ensureChannel(KehaiEventKind kind, KehaiSound sound) async {
    final channelId = channelIdFor(kind, sound);
    if (_liveChannels[kind] == channelId) return channelId;

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) {
      _liveChannels[kind] = channelId;
      return channelId;
    }

    try {
      await android.createNotificationChannel(
        AndroidNotificationChannel(
          channelId,
          AppStrings.notifyChannelName(kind),
          description: AppStrings.notifyChannelDescription(kind),
          importance: Importance.high,
          playSound: !sound.isSilent,
          sound: sound.isSilent
              ? null
              : RawResourceAndroidNotificationSound(sound.androidResource),
          enableVibration: !sound.isSilent,
        ),
      );
      // Retire every other sound's channel for this event, so Settings shows
      // exactly four Kehai channels however many times the user has changed
      // their mind.
      for (final other in KehaiSound.values) {
        final stale = channelIdFor(kind, other);
        if (stale == channelId) continue;
        await android.deleteNotificationChannel(channelId: stale);
      }
    } catch (error) {
      debugPrint('notification channel not updated: $error');
    }
    _liveChannels[kind] = channelId;
    return channelId;
  }

  /// The channel id for one event+sound pair. Public so the channel-per-sound
  /// naming is testable without a platform channel.
  static String channelIdFor(KehaiEventKind kind, KehaiSound sound) =>
      'kehai_evt_${kind.id}_${sound.id}';
}

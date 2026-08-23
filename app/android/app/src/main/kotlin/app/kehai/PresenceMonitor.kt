package app.kehai

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.Process
import android.provider.Settings

/**
 * Reads the three phone-side presence signals from kb/platform-android.md
 * and hands Dart raw values. Deliberately thin: no precedence, no
 * formatting, no idle arithmetic beyond remembering *when* the screen went
 * off. Everything that could be wrong in an interesting way lives in
 * `android_presence_mapper.dart`, where it can be unit-tested.
 *
 * Sources:
 *  - battery + charging: ACTION_BATTERY_CHANGED (sticky, runtime-only —
 *    it cannot be declared in the manifest).
 *  - screen state: ACTION_SCREEN_ON / ACTION_SCREEN_OFF / ACTION_USER_PRESENT
 *    (also runtime-only).
 *  - now-playing: MediaSessionManager.getActiveSessions, which requires our
 *    NotificationListenerService to be enabled by the user. Without the
 *    grant it throws SecurityException and we simply report no sessions.
 *  - foreground app: UsageStatsManager.queryEvents over the trailing ~60s
 *    window, requires the Usage Access special-access grant (checked via
 *    AppOpsManager, since queryEvents itself just silently returns nothing
 *    rather than throwing without it — unlike the media-session path above,
 *    so we check explicitly instead of inferring the grant from an empty
 *    result). Additionally gated on [setForegroundAppEnabled], the
 *    `shareFocusedApp` opt-in pushed down from Dart: "off" here means the
 *    poll loop doesn't run at all, not just that the result goes unused.
 *
 * ON-DEVICE VERIFICATION NEEDED: broadcast delivery, the notification
 * listener grant, the Usage Access grant + queryEvents behaviour, and
 * per-player MediaSession behaviour (Spotify/YouTube are each a little
 * different) can only be confirmed on real hardware.
 */
class PresenceMonitor(
    private val context: Context,
    private val onChange: () -> Unit,
) {
    private val handler = Handler(Looper.getMainLooper())

    private var batteryPercent: Int? = null
    private var charging: Boolean? = null
    private var screenOn: Boolean = true

    /** Epoch millis of the moment the screen went off; null while it's on. */
    private var screenOffSince: Long? = null

    private var started = false
    private var mediaSessionManager: MediaSessionManager? = null
    private var controllers: List<MediaController> = emptyList()

    /** The `shareFocusedApp` opt-in, pushed down via [setForegroundAppEnabled]. */
    private var foregroundAppEnabled = false
    private var foregroundPackage: String? = null

    private val foregroundAppPollIntervalMs = 30_000L
    private val foregroundAppLookbackMs = 60_000L

    private val foregroundAppRunnable = object : Runnable {
        override fun run() {
            if (!foregroundAppEnabled) return
            refreshForegroundApp()
            handler.postDelayed(this, foregroundAppPollIntervalMs)
        }
    }

    private val listenerComponent =
        ComponentName(context, KehaiNotificationListenerService::class.java)

    private val batteryReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context?, intent: Intent?) {
            if (intent != null) applyBatteryIntent(intent)
        }
    }

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context?, intent: Intent?) {
            when (intent?.action) {
                Intent.ACTION_SCREEN_ON, Intent.ACTION_USER_PRESENT -> setScreenOn(true)
                Intent.ACTION_SCREEN_OFF -> setScreenOn(false)
            }
        }
    }

    private val sessionsChangedListener =
        MediaSessionManager.OnActiveSessionsChangedListener { list ->
            bindControllers(list ?: emptyList())
            onChange()
        }

    private val controllerCallback = object : MediaController.Callback() {
        override fun onMetadataChanged(metadata: MediaMetadata?) = onChange()
        override fun onPlaybackStateChanged(state: android.media.session.PlaybackState?) = onChange()
        override fun onSessionDestroyed() {
            refreshSessions()
            onChange()
        }
    }

    fun start() {
        if (started) return
        started = true

        // registerReceiver returns the sticky ACTION_BATTERY_CHANGED intent
        // straight away, so this both subscribes and seeds the first value.
        val sticky = registerReceiverCompat(
            batteryReceiver,
            IntentFilter(Intent.ACTION_BATTERY_CHANGED),
        )
        if (sticky != null) applyBatteryIntent(sticky)

        registerReceiverCompat(
            screenReceiver,
            IntentFilter().apply {
                addAction(Intent.ACTION_SCREEN_ON)
                addAction(Intent.ACTION_SCREEN_OFF)
                addAction(Intent.ACTION_USER_PRESENT)
            },
        )

        screenOn = try {
            (context.getSystemService(Context.POWER_SERVICE) as PowerManager).isInteractive
        } catch (_: Exception) {
            true
        }
        // If we start up with the screen already off we have no idea how
        // long it's been off — leave the anchor null so Dart reports "no
        // idle signal" rather than inventing a fresh zero.
        screenOffSince = null

        startMediaSessions()

        handler.removeCallbacks(foregroundAppRunnable)
        if (foregroundAppEnabled) handler.post(foregroundAppRunnable)
    }

    fun stop() {
        if (!started) return
        started = false
        runCatching { context.unregisterReceiver(batteryReceiver) }
        runCatching { context.unregisterReceiver(screenReceiver) }
        runCatching {
            mediaSessionManager?.removeOnActiveSessionsChangedListener(sessionsChangedListener)
        }
        bindControllers(emptyList())
        mediaSessionManager = null
        handler.removeCallbacks(foregroundAppRunnable)
    }

    /**
     * The `shareFocusedApp` opt-in, pushed down from
     * `AndroidPresenceChannel.setForegroundAppEnabled`. Turning this on
     * starts the ~30s `UsageStatsManager` poll loop (immediately, plus a
     * fresh read right away); turning it off stops the loop AND clears any
     * previously-reported package, mirroring "off means we never look" —
     * the loop genuinely doesn't run, this isn't just Dart discarding a
     * value we kept reading anyway.
     */
    fun setForegroundAppEnabled(enabled: Boolean) {
        if (enabled == foregroundAppEnabled) return
        foregroundAppEnabled = enabled
        handler.removeCallbacks(foregroundAppRunnable)
        if (enabled) {
            handler.post(foregroundAppRunnable)
        } else if (foregroundPackage != null) {
            foregroundPackage = null
            onChange()
        }
    }

    private fun refreshForegroundApp() {
        val next = queryForegroundPackage()
        if (next == foregroundPackage) return
        foregroundPackage = next
        onChange()
    }

    /**
     * The latest MOVE_TO_FOREGROUND event in the trailing
     * [foregroundAppLookbackMs] window, or null if there's no Usage Access
     * grant (checked explicitly — `queryEvents` doesn't throw without the
     * grant, it just returns an empty iterator, so an empty result here is
     * ambiguous with "nothing changed foreground recently" unless we check
     * the grant ourselves first) or nothing was foregrounded in that
     * window.
     */
    private fun queryForegroundPackage(): String? {
        if (!hasUsageAccess()) return null
        return runCatching {
            val usm =
                context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val end = System.currentTimeMillis()
            val begin = end - foregroundAppLookbackMs
            val events = usm.queryEvents(begin, end)
            val event = UsageEvents.Event()
            var latestPackage: String? = null
            var latestTime = Long.MIN_VALUE
            while (events.hasNextEvent()) {
                events.getNextEvent(event)
                if (event.eventType == UsageEvents.Event.MOVE_TO_FOREGROUND &&
                    event.timeStamp >= latestTime
                ) {
                    latestTime = event.timeStamp
                    latestPackage = event.packageName
                }
            }
            latestPackage
        }.getOrNull()
    }

    /**
     * Whether the user has granted Kehai the Usage Access special access
     * (Settings > Apps > Special app access > Usage access), via the
     * `AppOpsManager` op backing it rather than a manifest permission —
     * `PACKAGE_USAGE_STATS` is a signature/privileged permission normal
     * apps can't hold, the OS instead tracks the grant as an app op the
     * user flips in that settings screen.
     */
    fun hasUsageAccess(): Boolean = runCatching {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName,
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                context.packageName,
            )
        }
        mode == AppOpsManager.MODE_ALLOWED
    }.getOrDefault(false)

    /** The payload `AndroidPresenceSnapshot.fromChannel` parses. */
    fun snapshot(): Map<String, Any?> = mapOf(
        "battery" to batteryPercent,
        "charging" to charging,
        "screen_on" to screenOn,
        "screen_off_since_millis" to screenOffSince,
        "media_listener_enabled" to isNotificationListenerEnabled(),
        "sessions" to sessionSnapshots(),
        "foreground_package" to foregroundPackage,
    )

    fun isNotificationListenerEnabled(): Boolean {
        // NotificationManagerCompat.getEnabledListenerPackages() would do
        // this too, but reading the Secure setting keeps the app module
        // free of an androidx dependency it otherwise doesn't need.
        val flat = runCatching {
            Settings.Secure.getString(context.contentResolver, "enabled_notification_listeners")
        }.getOrNull() ?: return false
        return flat.split(":").any { entry ->
            ComponentName.unflattenFromString(entry)?.packageName == context.packageName
        }
    }

    // --- battery ---

    private fun applyBatteryIntent(intent: Intent) {
        val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
        val nextPercent = if (level >= 0 && scale > 0) level * 100 / scale else null

        val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        val plugged = intent.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0)
        val nextCharging = when {
            status == BatteryManager.BATTERY_STATUS_CHARGING -> true
            status == BatteryManager.BATTERY_STATUS_FULL -> plugged != 0
            plugged != 0 -> true
            status == -1 -> null
            else -> false
        }

        if (nextPercent == batteryPercent && nextCharging == charging) return
        batteryPercent = nextPercent
        charging = nextCharging
        onChange()
    }

    // --- screen ---

    private fun setScreenOn(on: Boolean) {
        if (on == screenOn) return
        screenOn = on
        screenOffSince = if (on) null else System.currentTimeMillis()
        onChange()
    }

    // --- media sessions ---

    private fun startMediaSessions() {
        val manager = runCatching {
            context.getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
        }.getOrNull() ?: return
        mediaSessionManager = manager

        // Both of these throw SecurityException until the user enables the
        // notification listener. That's the expected default state, not an
        // error: now-playing just stays absent.
        runCatching {
            manager.addOnActiveSessionsChangedListener(
                sessionsChangedListener,
                listenerComponent,
                handler,
            )
        }
        refreshSessions()
    }

    private fun refreshSessions() {
        val manager = mediaSessionManager ?: return
        val active: List<MediaController> =
            runCatching { manager.getActiveSessions(listenerComponent) }
                .getOrNull() ?: emptyList()
        bindControllers(active)
    }

    private fun bindControllers(next: List<MediaController>) {
        controllers.forEach { runCatching { it.unregisterCallback(controllerCallback) } }
        controllers = next
        controllers.forEach {
            runCatching { it.registerCallback(controllerCallback, handler) }
        }
    }

    private fun sessionSnapshots(): List<Map<String, Any?>> {
        // getActiveSessions orders by priority (most recently active
        // first); Dart keeps that order and picks with its own rules.
        return controllers.mapNotNull { controller ->
            runCatching {
                val metadata = controller.metadata
                mapOf(
                    "package" to controller.packageName,
                    "label" to appLabel(controller.packageName),
                    "title" to metadata?.getString(MediaMetadata.METADATA_KEY_TITLE),
                    "artist" to (metadata?.getString(MediaMetadata.METADATA_KEY_ARTIST)
                        ?: metadata?.getString(MediaMetadata.METADATA_KEY_ALBUM_ARTIST)),
                    "album" to metadata?.getString(MediaMetadata.METADATA_KEY_ALBUM),
                    "state" to (controller.playbackState?.state ?: 0),
                )
            }.getOrNull()
        }
    }

    private fun appLabel(packageName: String?): String? {
        if (packageName.isNullOrEmpty()) return null
        return runCatching {
            val pm = context.packageManager
            @Suppress("DEPRECATION")
            pm.getApplicationLabel(pm.getApplicationInfo(packageName, 0)).toString()
        }.getOrNull()
    }

    private fun registerReceiverCompat(
        receiver: BroadcastReceiver,
        filter: IntentFilter,
    ): Intent? {
        // Android 14 (targetSdk 34+) wants an explicit exported flag.
        // NOT_EXPORTED is right here: everything we listen for is a
        // protected system broadcast, which is delivered regardless.
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.registerReceiver(receiver, filter)
        }
    }
}

package app.kehai

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
 *
 * ON-DEVICE VERIFICATION NEEDED: broadcast delivery, the notification
 * listener grant, and per-player MediaSession behaviour (Spotify/YouTube
 * are each a little different) can only be confirmed on real hardware.
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
    }

    /** The payload `AndroidPresenceSnapshot.fromChannel` parses. */
    fun snapshot(): Map<String, Any?> = mapOf(
        "battery" to batteryPercent,
        "charging" to charging,
        "screen_on" to screenOn,
        "screen_off_since_millis" to screenOffSince,
        "media_listener_enabled" to isNotificationListenerEnabled(),
        "sessions" to sessionSnapshots(),
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

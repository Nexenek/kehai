package app.kehai

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The `app.kehai/presence` platform channels, backed by [PresenceMonitor].
 *
 * This is a plain FlutterPlugin rather than MainActivity wiring on
 * purpose: the foreground service starts its own engine with no Activity
 * attached, and channels registered against an Activity simply don't exist
 * there. As a plugin it can be added to either engine — MainActivity adds
 * it to the UI engine, KehaiApplication adds it to the service's engine.
 */
class KehaiPresencePlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    private var appContext: Context? = null
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var monitor: PresenceMonitor? = null
    private var eventSink: EventChannel.EventSink? = null

    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val context = binding.applicationContext
        appContext = context

        // Built now, started lazily: both engines (UI and service) attach
        // this plugin, and only the one Dart actually asks should hold
        // broadcast receivers and MediaController callbacks.
        monitor = PresenceMonitor(context) { emitSnapshot() }

        methodChannel = MethodChannel(binding.binaryMessenger, CHANNEL_METHODS).apply {
            setMethodCallHandler(this@KehaiPresencePlugin)
        }
        eventChannel = EventChannel(binding.binaryMessenger, CHANNEL_EVENTS).apply {
            setStreamHandler(this@KehaiPresencePlugin)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        monitor?.stop()
        monitor = null
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        eventChannel?.setStreamHandler(null)
        eventChannel = null
        eventSink = null
        appContext = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getSnapshot" -> {
                monitor?.start()
                result.success(monitor?.snapshot() ?: emptyMap<String, Any?>())
            }
            "isNotificationListenerEnabled" ->
                result.success(monitor?.isNotificationListenerEnabled() ?: false)
            "openNotificationListenerSettings" ->
                result.success(openNotificationListenerSettings())
            "hasUsageAccess" -> result.success(monitor?.hasUsageAccess() ?: false)
            "getForegroundAppPreview" ->
                result.success(monitor?.queryForegroundPackagePreview())
            "openUsageAccessSettings" -> result.success(openUsageAccessSettings())
            "setForegroundAppEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                // Mirrors "getSnapshot": make sure the monitor is actually
                // running before asking it to change what it polls.
                monitor?.start()
                monitor?.setForegroundAppEnabled(enabled)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        monitor?.start()
        emitSnapshot()
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    /**
     * Channel calls must happen on the platform thread. The monitor's
     * callbacks already arrive on the main looper (its receivers and
     * MediaController callbacks are all main-thread), but posting keeps
     * that true even if a future source moves off it.
     */
    private fun emitSnapshot() {
        val snapshot = monitor?.snapshot() ?: return
        mainHandler.post { eventSink?.success(snapshot) }
    }

    /**
     * Deep-link to Settings > Notification access. Started from the
     * application context, so it needs NEW_TASK; some heavily-skinned ROMs
     * hide this screen entirely, hence the false return rather than a
     * thrown error the UI would have to translate.
     */
    private fun openNotificationListenerSettings(): Boolean {
        val context = appContext ?: return false
        val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return runCatching { context.startActivity(intent) }.isSuccess
    }

    /**
     * Deep-link to Settings > Apps > Special app access > Usage access —
     * the grant `PresenceMonitor.hasUsageAccess` checks for the
     * "focused-app status" feature (kb/platform-android.md's "Foreground
     * app" row). Same false-on-hidden-ROM-screen contract as
     * [openNotificationListenerSettings].
     */
    private fun openUsageAccessSettings(): Boolean {
        val context = appContext ?: return false
        val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return runCatching { context.startActivity(intent) }.isSuccess
    }

    private companion object {
        const val CHANNEL_METHODS = "app.kehai/presence"
        const val CHANNEL_EVENTS = "app.kehai/presence_events"
    }
}

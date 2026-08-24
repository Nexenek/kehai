package app.kehai

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.time.Duration
import java.time.Instant
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter

/**
 * The `app.kehai/vitals` platform channel: today's step count and the
 * newest heart-rate sample, read from **Health Connect** — the one bridge
 * Samsung Health, Garmin Connect, Wear OS/Pixel Watch and Zepp/Amazfit all
 * sync into (kb/platform-android.md, "Smartwatches (2026)").
 *
 * Same plugin-not-Activity-wiring shape as [KehaiPresencePlugin], and for
 * the same reason: the foreground service runs a second FlutterEngine with
 * no Activity attached, and [readVitals] has to work there — that isolate
 * is the one that owns the heartbeat once the app is backgrounded. Only
 * [requestPermissions] needs an Activity (it launches the permission UI),
 * so that's the only method that fails politely when this plugin happens to
 * be living in the service's engine.
 *
 * Nothing here ever throws at Dart: every Health Connect call is wrapped,
 * because a missing provider / revoked grant / OEM oddity must degrade to
 * "no reading" rather than take the heartbeat loop down with it. Every one
 * of those swallowing branches logs under [TAG] instead — this feature is
 * un-runnable in CI and hard to reproduce by hand, so `adb logcat -s
 * KehaiVitals` is the only debugging surface it has.
 */
class KehaiVitalsPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler {

    private var appContext: Context? = null
    private var methodChannel: MethodChannel? = null
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null

    /** The in-flight [requestPermissions] call, answered from whichever result arrives. */
    private var pendingPermissionResult: MethodChannel.Result? = null

    private var scope: CoroutineScope? = null

    /**
     * Held as fields, NOT as `::onActivityResult` method references at the
     * add/remove call sites: each `::` evaluation allocates a *new* function
     * object, so `removeActivityResultListener(::onActivityResult)` removes
     * nothing and every Activity re-attach leaks another listener onto the
     * binding. (This shipped once — the leak is why they're fields now.)
     */
    private val activityResultListener =
        PluginRegistry.ActivityResultListener { requestCode, resultCode, data ->
            onActivityResult(requestCode, resultCode, data)
        }

    private val permissionsResultListener =
        PluginRegistry.RequestPermissionsResultListener { requestCode, permissions, grantResults ->
            onRequestPermissionsResult(requestCode, permissions, grantResults)
        }

    // Health Connect's suspend API is fully async underneath (AIDL / platform
    // service callbacks), so Main is the right dispatcher: no blocking work
    // runs on it, and MethodChannel results must be delivered there anyway.
    private fun scope(): CoroutineScope =
        scope ?: CoroutineScope(Dispatchers.Main + SupervisorJob()).also { scope = it }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler(this@KehaiVitalsPlugin)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        appContext = null
        scope?.cancel()
        scope = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        activity = binding.activity
        binding.addActivityResultListener(activityResultListener)
        binding.addRequestPermissionsResultListener(permissionsResultListener)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onDetachedFromActivity() {
        activityBinding?.removeActivityResultListener(activityResultListener)
        activityBinding?.removeRequestPermissionsResultListener(permissionsResultListener)
        activityBinding = null
        activity = null
        // A permission flow can't survive the Activity that launched it.
        pendingPermissionResult?.let {
            Log.w(TAG, "activity detached with a permission request still pending")
            it.success(false)
        }
        pendingPermissionResult = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getAvailability" -> result.success(availability())
            "hasPermissions" -> scope().launch {
                result.success(runCatching { hasPermissions() }.getOrDefault(false))
            }
            "hasBackgroundPermission" -> scope().launch {
                result.success(runCatching { hasBackgroundPermission() }.getOrDefault(false))
            }
            "requestPermissions" -> requestPermissions(result)
            "openHealthConnectSettings" -> result.success(openHealthConnectSettings())
            "readVitals" -> scope().launch {
                result.success(runCatching { readVitals() }.getOrElse { emptyVitals() })
            }
            else -> result.notImplemented()
        }
    }

    // --- availability -----------------------------------------------------

    /**
     * "available" | "needsUpdate" | "unavailable".
     *
     * The SDK-level check is guarded by an explicit API-level test rather
     * than left to `getSdkStatus` alone: `connect-client` is built against
     * minSdk 26 and merged in with `tools:overrideLibrary` (see the
     * manifest), so on a 24/25 device its classes must never be touched at
     * all. Health Connect itself needs Android 9 regardless.
     */
    private fun availability(): String {
        val context = appContext ?: return UNAVAILABLE
        if (Build.VERSION.SDK_INT < MIN_HEALTH_CONNECT_SDK) return UNAVAILABLE
        return try {
            when (val status = HealthConnectClient.getSdkStatus(context)) {
                HealthConnectClient.SDK_AVAILABLE -> AVAILABLE
                HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED -> {
                    Log.i(TAG, "health connect provider needs an update (status=$status)")
                    NEEDS_UPDATE
                }
                else -> {
                    Log.i(TAG, "health connect unavailable (status=$status)")
                    UNAVAILABLE
                }
            }
        } catch (t: Throwable) {
            Log.w(TAG, "getSdkStatus threw ${t.javaClass.simpleName}: ${t.message}")
            UNAVAILABLE
        }
    }

    private fun client(): HealthConnectClient? {
        val context = appContext ?: return null
        if (availability() != AVAILABLE) return null
        return try {
            HealthConnectClient.getOrCreate(context)
        } catch (t: Throwable) {
            Log.w(TAG, "getOrCreate threw ${t.javaClass.simpleName}: ${t.message}")
            null
        }
    }

    // --- permissions ------------------------------------------------------

    private suspend fun grantedPermissions(): Set<String> {
        val client = client() ?: return emptySet()
        return try {
            client.permissionController.getGrantedPermissions()
        } catch (t: Throwable) {
            Log.w(
                TAG,
                "getGrantedPermissions threw ${t.javaClass.simpleName}: ${t.message}",
            )
            emptySet()
        }
    }

    /**
     * Both reads granted. The background-read permission is deliberately NOT
     * part of this answer: it doesn't exist on older providers, and a phone
     * that can only read vitals while Kehai is on screen still reports
     * something useful — treating it as required would turn a partial grant
     * into a dead feature. [hasBackgroundPermission] reports it separately
     * so the UI can say so out loud instead.
     */
    private suspend fun hasPermissions(): Boolean =
        grantedPermissions().containsAll(REQUIRED_PERMISSIONS)

    /**
     * Whether reads are allowed while Kehai is off screen. This is the
     * difference between "vitals update all day" and "vitals update when you
     * open the app" — the foreground service is what does the reading, and
     * without this grant Health Connect refuses it every time the app isn't
     * visible (the exact symptom: vitals that only move when you open the
     * app).
     */
    private suspend fun hasBackgroundPermission(): Boolean =
        grantedPermissions().contains(HealthPermission.PERMISSION_READ_HEALTH_DATA_IN_BACKGROUND)

    /**
     * Launches the permission UI and answers with whether the two reads
     * ended up granted. Two genuinely different flows:
     *
     * - **Android 14+** (health permissions live in the platform): these are
     *   ordinary runtime permissions, so `Activity.requestPermissions` is
     *   the flow. `PermissionController`'s contract is NOT usable here — on
     *   34+ it delegates to `ActivityResultContracts.RequestMultiplePermissions`,
     *   whose intent carries the AndroidX-internal action
     *   `androidx.activity.result.contract.action.REQUEST_PERMISSIONS`. That
     *   intent is only ever meant to be *intercepted* by ComponentActivity's
     *   `ActivityResultRegistry`, never actually started; handing it to
     *   `startActivityForResult` resolves to nothing at all, which is
     *   precisely the "tapping turn on did nothing" bug this replaced.
     * - **Below 14** (Health Connect is a separate APK): the contract builds
     *   a real, package-targeted `androidx.health.ACTION_REQUEST_PERMISSIONS`
     *   intent, and `startActivityForResult` is right.
     *
     * `FlutterActivity` is a plain `android.app.Activity`, not a
     * `ComponentActivity`, so `registerForActivityResult` isn't an option on
     * either path — both go through [ActivityPluginBinding]'s listeners.
     */
    private fun requestPermissions(result: MethodChannel.Result) {
        val activity = this.activity
        if (activity == null) {
            // The service engine's copy of this plugin has no Activity —
            // expected there, a real problem if it ever shows up from the UI.
            Log.w(TAG, "requestPermissions: no activity attached, cannot ask")
            result.success(false)
            return
        }
        val availability = availability()
        if (availability != AVAILABLE) {
            Log.w(TAG, "requestPermissions: nothing to ask, availability=$availability")
            result.success(false)
            return
        }
        if (pendingPermissionResult != null) {
            Log.w(TAG, "requestPermissions: a request is already in flight, ignoring")
            result.success(false)
            return
        }

        pendingPermissionResult = result
        val launched = if (Build.VERSION.SDK_INT >= ANDROID_14) {
            launchPlatformPermissionRequest(activity)
        } else {
            launchProviderPermissionRequest(activity)
        }
        if (!launched) {
            pendingPermissionResult = null
            result.success(false)
        }
    }

    /** Android 14+: health permissions are runtime permissions. */
    private fun launchPlatformPermissionRequest(activity: Activity): Boolean = try {
        val permissions = REQUESTED_PERMISSIONS.toTypedArray()
        Log.i(TAG, "requesting runtime health permissions: ${permissions.joinToString()}")
        activity.requestPermissions(permissions, PERMISSION_REQUEST_CODE)
        true
    } catch (t: Throwable) {
        Log.e(TAG, "requestPermissions threw ${t.javaClass.simpleName}: ${t.message}", t)
        false
    }

    /** Below Android 14: the Health Connect APK's own permission screen. */
    private fun launchProviderPermissionRequest(activity: Activity): Boolean = try {
        val intent = PermissionController.createRequestPermissionResultContract()
            .createIntent(activity, REQUESTED_PERMISSIONS)
        Log.i(TAG, "starting provider permission screen: action=${intent.action}")
        activity.startActivityForResult(intent, PERMISSION_REQUEST_CODE)
        true
    } catch (t: Throwable) {
        Log.e(
            TAG,
            "provider permission screen failed ${t.javaClass.simpleName}: ${t.message}",
            t,
        )
        false
    }

    /**
     * Both result paths answer the same way, and neither trusts what it was
     * handed: what the user actually ended up granting is a question only
     * Health Connect can answer, and re-reading it can't disagree with
     * reality the way a parsed result can (a provider that returns nothing
     * on cancel, a grant changed in settings mid-flow).
     */
    private fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PERMISSION_REQUEST_CODE) return false
        Log.i(TAG, "permission screen returned resultCode=$resultCode")
        answerPendingPermissionRequest()
        return true
    }

    private fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>?,
        grantResults: IntArray?,
    ): Boolean {
        if (requestCode != PERMISSION_REQUEST_CODE) return false
        val summary = permissions
            ?.mapIndexed { i, permission ->
                val granted = grantResults?.getOrNull(i) == PackageManager.PERMISSION_GRANTED
                "${permission.substringAfterLast('.')}=$granted"
            }
            ?.joinToString()
            ?: "none"
        Log.i(TAG, "runtime permission result: $summary")
        answerPendingPermissionRequest()
        return true
    }

    private fun answerPendingPermissionRequest() {
        val pending = pendingPermissionResult ?: return
        pendingPermissionResult = null
        scope().launch {
            val granted = runCatching { hasPermissions() }.getOrDefault(false)
            val background = runCatching { hasBackgroundPermission() }.getOrDefault(false)
            Log.i(TAG, "after request: reads granted=$granted, background granted=$background")
            pending.success(granted)
        }
    }

    /**
     * Deep-links to Health Connect's own settings, where a grant that the
     * sheet couldn't obtain (already-denied runtime permissions stop
     * prompting, some OEM builds skip the sheet entirely) can still be given
     * by hand — including background access, which is the one the request
     * flow most often comes back without. False when nothing on this phone
     * can handle it, so the caller can say so rather than appearing to work.
     */
    private fun openHealthConnectSettings(): Boolean {
        val context = appContext ?: return false
        if (Build.VERSION.SDK_INT < MIN_HEALTH_CONNECT_SDK) return false
        // The actions are spelled out here rather than read off
        // `HealthConnectClient.healthConnectSettingsAction`: that accessor is
        // deprecated-hidden in 1.1.0 (present in the bytecode, unresolvable
        // from Kotlin). Both are tried in order — the platform screen first
        // on 14+, the APK's own below — because which one exists depends on
        // the provider, not only on the API level.
        val actions = if (Build.VERSION.SDK_INT >= ANDROID_14) {
            listOf(PLATFORM_SETTINGS_ACTION, PROVIDER_SETTINGS_ACTION)
        } else {
            listOf(PROVIDER_SETTINGS_ACTION, PLATFORM_SETTINGS_ACTION)
        }
        for (action in actions) {
            // Started from the application context (the service's engine has
            // no Activity either), so it needs its own task.
            val intent = Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                context.startActivity(intent)
                Log.i(TAG, "opened health connect settings: action=$action")
                return true
            } catch (t: Throwable) {
                Log.w(
                    TAG,
                    "health connect settings ($action) unresolvable: " +
                        "${t.javaClass.simpleName}: ${t.message}",
                )
            }
        }
        return false
    }

    // --- reads ------------------------------------------------------------

    /**
     * "no reading", in the shape Dart expects. An instance function rather
     * than a companion `val` on purpose: touching *any* non-const companion
     * member runs the companion's initialiser, which resolves Health
     * Connect permission names — and on an API 24/25 phone the whole point
     * of [availability]'s version guard is that no Health Connect class is
     * ever loaded.
     */
    private fun emptyVitals(): Map<String, Any?> = mapOf(
        "stepsToday" to null,
        "bpm" to null,
        "bpmAt" to null,
    )

    /**
     * `{"stepsToday": Long?, "bpm": Double?, "bpmAt": String?}` — every key
     * independently nullable, and an all-null map on any failure. Callable
     * with no Activity: this runs in the foreground service's engine most of
     * the time.
     *
     * Steps are aggregated from **local midnight** (a `LocalDateTime` range,
     * so "today" means the phone's today, not UTC's). Heart rate is the
     * newest single sample in the last two hours — records arrive as series,
     * so the newest record is not necessarily where the newest sample lives.
     *
     * Without READ_HEALTH_DATA_IN_BACKGROUND every call from the backgrounded
     * service throws `SecurityException` here; the logging below is what
     * makes that visible rather than looking like "the watch never syncs".
     */
    private suspend fun readVitals(): Map<String, Any?> {
        val client = client() ?: return emptyVitals()
        val granted = grantedPermissions()
        if (granted.isEmpty()) {
            Log.w(TAG, "readVitals: no permissions granted, nothing to read")
            return emptyVitals()
        }

        val steps = if (granted.contains(READ_STEPS)) {
            readStepsToday(client)
        } else {
            Log.w(TAG, "readVitals: READ_STEPS not granted")
            null
        }
        val sample = if (granted.contains(READ_HEART_RATE)) {
            readLatestHeartRate(client)
        } else {
            Log.w(TAG, "readVitals: READ_HEART_RATE not granted")
            null
        }

        Log.i(TAG, "readVitals: steps=$steps, bpm=${sample?.beatsPerMinute}")
        return mapOf(
            "stepsToday" to steps,
            "bpm" to sample?.beatsPerMinute?.toDouble(),
            "bpmAt" to sample?.time?.let { DateTimeFormatter.ISO_INSTANT.format(it) },
        )
    }

    private suspend fun readStepsToday(client: HealthConnectClient): Long? = try {
        val now = LocalDateTime.now()
        val response = client.aggregate(
            AggregateRequest(
                metrics = setOf(StepsRecord.COUNT_TOTAL),
                timeRangeFilter = TimeRangeFilter.between(
                    now.toLocalDate().atStartOfDay(),
                    now,
                ),
            )
        )
        response[StepsRecord.COUNT_TOTAL]
    } catch (t: Throwable) {
        // SecurityException is the loud one: either the grant was revoked, or
        // this is a background read without READ_HEALTH_DATA_IN_BACKGROUND.
        Log.w(TAG, "steps read failed ${t.javaClass.simpleName}: ${t.message}")
        null
    }

    private suspend fun readLatestHeartRate(
        client: HealthConnectClient,
    ): HeartRateRecord.Sample? = try {
        val now = Instant.now()
        val response = client.readRecords(
            ReadRecordsRequest(
                recordType = HeartRateRecord::class,
                timeRangeFilter = TimeRangeFilter.between(
                    now.minus(HEART_RATE_WINDOW),
                    now,
                ),
                ascendingOrder = false,
                pageSize = HEART_RATE_PAGE_SIZE,
            )
        )
        response.records
            .flatMap { it.samples }
            .maxByOrNull { it.time }
    } catch (t: Throwable) {
        Log.w(TAG, "heart-rate read failed ${t.javaClass.simpleName}: ${t.message}")
        null
    }

    private companion object {
        const val TAG = "KehaiVitals"

        const val CHANNEL = "app.kehai/vitals"

        const val AVAILABLE = "available"
        const val NEEDS_UPDATE = "needsUpdate"
        const val UNAVAILABLE = "unavailable"

        /** Health Connect requires Android 9; below that nothing is loaded. */
        const val MIN_HEALTH_CONNECT_SDK = Build.VERSION_CODES.P

        /** Where health permissions became ordinary runtime permissions. */
        const val ANDROID_14 = Build.VERSION_CODES.UPSIDE_DOWN_CAKE

        const val PERMISSION_REQUEST_CODE = 0x4845 // "HE"

        /** Health Connect's settings screen, in the platform (Android 14+). */
        const val PLATFORM_SETTINGS_ACTION =
            "android.health.connect.action.HEALTH_HOME_SETTINGS"

        /** …and in the standalone Health Connect app, below that. */
        const val PROVIDER_SETTINGS_ACTION =
            "androidx.health.ACTION_HEALTH_CONNECT_SETTINGS"

        /** How far back a heart-rate sample may be and still be worth reading. */
        val HEART_RATE_WINDOW: Duration = Duration.ofHours(2)

        /**
         * Watches batch-sync, so two hours can be a fair few series records;
         * 50 newest-first is plenty to find the freshest sample without
         * paging.
         */
        const val HEART_RATE_PAGE_SIZE = 50

        /**
         * `getReadPermission(KClass)` rather than the `READ_STEPS` /
         * `READ_HEART_RATE` constants: those are marked `internal` in the
         * Kotlin API surface (they're only public in the bytecode), so this
         * is the supported way to name a record type's read permission.
         */
        val READ_STEPS: String = HealthPermission.getReadPermission(StepsRecord::class)
        val READ_HEART_RATE: String =
            HealthPermission.getReadPermission(HeartRateRecord::class)

        val REQUIRED_PERMISSIONS = setOf(READ_STEPS, READ_HEART_RATE)

        /**
         * What we *ask* for. The background read is the one that makes this
         * feature actually work while Kehai is off screen (the foreground
         * service does the reading), but it only exists on Android 14+
         * providers — asking for it on an older one simply gets it dropped
         * from the sheet, which is why it's not in [REQUIRED_PERMISSIONS].
         */
        val REQUESTED_PERMISSIONS = REQUIRED_PERMISSIONS +
            HealthPermission.PERMISSION_READ_HEALTH_DATA_IN_BACKGROUND
    }
}

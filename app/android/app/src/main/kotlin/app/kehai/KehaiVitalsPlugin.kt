package app.kehai

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Build
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
 * [requestPermissions] needs an Activity (it launches Health Connect's own
 * permission UI), so that's the only method that fails politely when this
 * plugin happens to be living in the service's engine.
 *
 * Nothing here ever throws at Dart: every Health Connect call is wrapped,
 * because a missing provider / revoked grant / OEM oddity must degrade to
 * "no reading" rather than take the heartbeat loop down with it.
 *
 * ON-DEVICE VERIFICATION NEEDED: Health Connect can't be exercised on an
 * emulator without the provider app, and the background-read permission
 * (`READ_HEALTH_DATA_IN_BACKGROUND`) only exists on Android 14+ providers —
 * see the manifest comment.
 */
class KehaiVitalsPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler {

    private var appContext: Context? = null
    private var methodChannel: MethodChannel? = null
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null

    /** The in-flight [requestPermissions] call, answered from the activity result. */
    private var pendingPermissionResult: MethodChannel.Result? = null

    private var scope: CoroutineScope? = null

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
        binding.addActivityResultListener(::onActivityResult)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onDetachedFromActivity() {
        activityBinding?.removeActivityResultListener(::onActivityResult)
        activityBinding = null
        activity = null
        // A permission flow can't survive the Activity that launched it.
        pendingPermissionResult?.success(false)
        pendingPermissionResult = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getAvailability" -> result.success(availability())
            "hasPermissions" -> scope().launch {
                result.success(runCatching { hasPermissions() }.getOrDefault(false))
            }
            "requestPermissions" -> requestPermissions(result)
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
            when (HealthConnectClient.getSdkStatus(context)) {
                HealthConnectClient.SDK_AVAILABLE -> AVAILABLE
                HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED -> NEEDS_UPDATE
                else -> UNAVAILABLE
            }
        } catch (t: Throwable) {
            UNAVAILABLE
        }
    }

    private fun client(): HealthConnectClient? {
        val context = appContext ?: return null
        if (availability() != AVAILABLE) return null
        return try {
            HealthConnectClient.getOrCreate(context)
        } catch (t: Throwable) {
            null
        }
    }

    // --- permissions ------------------------------------------------------

    /**
     * Both reads granted. The background-read permission is deliberately NOT
     * part of this answer: it doesn't exist on older providers, and a phone
     * that can only read vitals while Kehai is on screen still reports
     * something useful — treating it as required would turn a partial grant
     * into a dead feature.
     */
    private suspend fun hasPermissions(): Boolean {
        val client = client() ?: return false
        return try {
            client.permissionController.getGrantedPermissions().containsAll(REQUIRED_PERMISSIONS)
        } catch (t: Throwable) {
            false
        }
    }

    /**
     * Launches Health Connect's own permission UI and answers with whether
     * the two reads ended up granted.
     *
     * `startActivityForResult` + [ActivityPluginBinding]'s result listener
     * rather than `registerForActivityResult`: `FlutterActivity` is a plain
     * `android.app.Activity`, not a `ComponentActivity`, so there's no
     * activity-result registry to register against. The contract still does
     * the work of building the right intent for this device's provider
     * (platform on 14+, the APK's own screen below that).
     */
    private fun requestPermissions(result: MethodChannel.Result) {
        val activity = this.activity
        if (activity == null || availability() != AVAILABLE) {
            result.success(false)
            return
        }
        if (pendingPermissionResult != null) {
            // A flow is already on screen — don't stack a second one.
            result.success(false)
            return
        }
        val intent: Intent = try {
            PermissionController.createRequestPermissionResultContract()
                .createIntent(activity, REQUESTED_PERMISSIONS)
        } catch (t: Throwable) {
            result.success(false)
            return
        }
        pendingPermissionResult = result
        try {
            activity.startActivityForResult(intent, PERMISSION_REQUEST_CODE)
        } catch (t: Throwable) {
            pendingPermissionResult = null
            result.success(false)
        }
    }

    /**
     * The contract's own `parseResult` is skipped on purpose: what the user
     * actually ended up granting is a question only Health Connect can
     * answer, and re-reading it can't disagree with reality the way a parsed
     * result set can (a provider that returns nothing on cancel, a grant
     * changed in settings mid-flow).
     */
    private fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PERMISSION_REQUEST_CODE) return false
        val pending = pendingPermissionResult ?: return true
        pendingPermissionResult = null
        scope().launch { pending.success(hasPermissions()) }
        return true
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
     */
    private suspend fun readVitals(): Map<String, Any?> {
        val client = client() ?: return emptyVitals()
        val granted = try {
            client.permissionController.getGrantedPermissions()
        } catch (t: Throwable) {
            return emptyVitals()
        }

        val steps = if (granted.contains(READ_STEPS)) {
            readStepsToday(client)
        } else {
            null
        }
        val sample = if (granted.contains(READ_HEART_RATE)) {
            readLatestHeartRate(client)
        } else {
            null
        }

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
        // SecurityException (grant revoked between the check and the read),
        // RemoteException (provider restarting), anything else the provider
        // decides to throw: no reading, never a crash.
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
        null
    }

    private companion object {
        const val CHANNEL = "app.kehai/vitals"

        const val AVAILABLE = "available"
        const val NEEDS_UPDATE = "needsUpdate"
        const val UNAVAILABLE = "unavailable"

        /** Health Connect requires Android 9; below that nothing is loaded. */
        const val MIN_HEALTH_CONNECT_SDK = Build.VERSION_CODES.P

        const val PERMISSION_REQUEST_CODE = 0x4845 // "HE"

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

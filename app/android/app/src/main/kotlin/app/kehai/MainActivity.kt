package app.kehai

import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    /**
     * Adds the presence and vitals channels to the UI engine. The
     * foreground service's engine gets the same plugins from
     * [KehaiApplication] — see that class for why registration has to
     * happen in two places.
     *
     * [KehaiVitalsPlugin] is the one that genuinely needs *both*
     * registrations to do different jobs: the service's copy does the
     * Health Connect reads, and this one is the only copy that can launch
     * the permission sheet (it's the only one with an Activity).
     *
     * The updates channel below is registered here and nowhere else, on
     * purpose: it exists to start an Activity (the system installer's
     * confirm sheet), which the background isolate could never do, and
     * updates are a thing a person is looking at the app to accept.
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(KehaiPresencePlugin())
        flutterEngine.plugins.add(KehaiVitalsPlugin())
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATES_CHANNEL)
            .setMethodCallHandler(::onUpdatesCall)
    }

    /**
     * The Android half of in-app updates — two methods, no plugin:
     *
     *  - `cacheDir` tells Dart where it is allowed to put the downloaded
     *    APK. It has to come from here because it must match what
     *    `res/xml/file_paths.xml` scopes the FileProvider to.
     *  - `installApk` hands that file to the system installer.
     */
    private fun onUpdatesCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "cacheDir" -> result.success(cacheDir.absolutePath)
            "installApk" -> installApk(call.arguments as? String, result)
            else -> result.notImplemented()
        }
    }

    /**
     * Fires ACTION_VIEW at the downloaded APK, which is what opens the
     * platform's own "update Kehai?" sheet.
     *
     * A `content://` URI, never a `file://` one: passing a file URI across
     * a process boundary has thrown FileUriExposedException since Nougat,
     * and the package installer is very much another process. The one-shot
     * FLAG_GRANT_READ_URI_PERMISSION is what lets it read a file inside our
     * private cache dir without the file being world-readable.
     *
     * Everything after this is the OS's: the "allow Kehai to install apps"
     * toggle if it hasn't been granted, the confirm tap, and the in-place
     * upgrade (same keystore, so the couple's data survives). We do not
     * quit — Android replaces us.
     */
    private fun installApk(path: String?, result: MethodChannel.Result) {
        if (path.isNullOrEmpty()) {
            result.error("no_path", "installApk needs a file path", null)
            return
        }
        val apk = File(path)
        if (!apk.isFile) {
            result.error("missing_apk", "no file at $path", null)
            return
        }
        try {
            val uri = FileProvider.getUriForFile(this, "$packageName.updates", apk)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, APK_MIME_TYPE)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            result.success(null)
        } catch (error: Exception) {
            // Nothing to clean up: the APK stays in the cache dir and the
            // running app is untouched, so a retry is just another tap.
            result.error("install_failed", error.message, null)
        }
    }

    private companion object {
        /** Must match AndroidUpdateInstaller.channelName in Dart. */
        const val UPDATES_CHANNEL = "kehai/updates"
        const val APK_MIME_TYPE = "application/vnd.android.package-archive"
    }
}

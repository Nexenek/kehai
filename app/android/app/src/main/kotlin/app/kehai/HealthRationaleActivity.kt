package app.kehai

import android.app.Activity
import android.app.AlertDialog
import android.os.Bundle

/**
 * The privacy-rationale screen Health Connect requires an app to expose
 * before it will hand over health permissions: it's launched with
 * `ACTION_SHOW_PERMISSIONS_RATIONALE` (pre-34 providers) or
 * `VIEW_PERMISSION_USAGE` + the HEALTH_PERMISSIONS category via the
 * `ViewPermissionUsageActivity` alias (Android 14+) — see AndroidManifest.
 *
 * Deliberately the smallest thing that can honestly answer "where does my
 * heart rate go": one dialog, one paragraph, no Flutter engine. Kehai has
 * no privacy policy URL to point at because it has no service to have a
 * policy about — the data goes to the couple's own server and nowhere else,
 * which is exactly what the copy says.
 */
class HealthRationaleActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert)
            .setTitle(R.string.health_rationale_title)
            .setMessage(R.string.health_rationale_message)
            .setPositiveButton(android.R.string.ok) { _, _ -> finish() }
            .setOnDismissListener { finish() }
            .show()
    }
}

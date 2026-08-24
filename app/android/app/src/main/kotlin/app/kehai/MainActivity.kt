package app.kehai

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

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
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(KehaiPresencePlugin())
        flutterEngine.plugins.add(KehaiVitalsPlugin())
    }
}

package app.kehai

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    /**
     * Adds the presence channels to the UI engine. The foreground
     * service's engine gets the same plugin from [KehaiApplication] — see
     * that class for why registration has to happen in two places.
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(KehaiPresencePlugin())
    }
}

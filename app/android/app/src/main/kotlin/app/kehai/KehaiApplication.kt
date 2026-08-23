package app.kehai

import android.app.Application
import com.pravera.flutter_foreground_task.FlutterForegroundTaskLifecycleListener
import com.pravera.flutter_foreground_task.FlutterForegroundTaskPlugin
import com.pravera.flutter_foreground_task.FlutterForegroundTaskStarter
import io.flutter.embedding.engine.FlutterEngine

/**
 * Exists for exactly one reason: the foreground service spins up a SECOND
 * FlutterEngine for the background Dart isolate, and that engine only gets
 * the plugins listed in GeneratedPluginRegistrant (pub packages). Our own
 * app-module plugin isn't in there, so without this hook the background
 * isolate would throw MissingPluginException the moment it asked for
 * battery / screen / now-playing.
 *
 * flutter_foreground_task hands us the engine right after it's constructed
 * and before it runs the Dart callback, which is the correct window to add
 * a plugin. Application.onCreate runs on every process start — including
 * when Android restarts the process for the service alone, with no
 * Activity — so the listener is always registered in time.
 *
 * (The UI engine gets the same plugin from MainActivity instead.)
 */
class KehaiApplication : Application() {

    private val taskLifecycleListener = object : FlutterForegroundTaskLifecycleListener {
        override fun onEngineCreate(flutterEngine: FlutterEngine?) {
            flutterEngine?.plugins?.add(KehaiPresencePlugin())
        }

        override fun onTaskStart(starter: FlutterForegroundTaskStarter) = Unit
        override fun onTaskRepeatEvent() = Unit
        override fun onTaskDestroy() = Unit
        override fun onEngineWillDestroy() = Unit
    }

    override fun onCreate() {
        super.onCreate()
        FlutterForegroundTaskPlugin.addTaskLifecycleListener(taskLifecycleListener)
    }
}

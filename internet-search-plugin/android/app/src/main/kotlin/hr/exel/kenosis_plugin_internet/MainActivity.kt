package hr.exel.kenosis_plugin_internet

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The plugin app's launcher activity. The service (InternetPluginService)
 * runs in the same process, so the UI can read the in-process fetch log
 * (InternetPluginService.snapshotFetchLogJson) directly — no binder round-trip
 * needed, just a MethodChannel hop.
 */
class MainActivity : FlutterActivity() {

    private val channel = "kenosis_plugin/ui"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getFetchLog" -> {
                        result.success(InternetPluginService.snapshotFetchLogJson())
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
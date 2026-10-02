package hr.exel.kenosis_plugin_livecast

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/**
 * The plugin app's launcher activity. The service (LivecastPluginService)
 * runs in the same process, so the status screen reads the live state
 * directly — no binder round-trip needed, just a MethodChannel hop.
 */
class MainActivity : FlutterActivity() {

    private val channel = "kenosis_livecast/ui"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getStatus" -> result.success(snapshotStatusJson())
                    "openExternalUrl" -> {
                        // Play Store hand-off (Get Kenosis AI / About). The
                        // plugin holds INTERNET — unlike the offline host —
                        // so a user-initiated store link is sanctioned here.
                        // ACTION_VIEW: the Play app intercepts its own deep
                        // links; startActivity is not subject to package
                        // visibility, so no <queries> entry is needed.
                        val url = call.argument<String>("url")
                        if (url.isNullOrBlank()) {
                            result.error("badArgs", "url missing", null)
                        } else {
                            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                            result.success(runCatching { startActivity(intent) }.isSuccess)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** Live status for the plugin's own launcher screen (in-process). The
     *  service may not exist yet (very early launch) — fall back to a blank
     *  state so the screen renders zeros instead of crashing. */
    private fun snapshotStatusJson(): String {
        val state = stateRef ?: LivecastState()
        val server = serverRef
        val json = JSONObject()
            .put("serverRunning", (server?.boundPort ?: -1) > 0)
            .put("port", server?.boundPort ?: -1)
            .put("sessionEpoch", state.sessionEpoch)
            .put("sessionElapsedMs", state.sessionElapsedMs)
            .put("segments", state.segmentCount)
            .put("digests", state.digestCount)
        return json.toString()
    }

    companion object {
        private const val TAG = "LivecastUi"

        /** Set by [LivecastPluginService.onCreate] (same process) so the UI
         *  can read the live state before/without the host binding. */
        @Volatile var stateRef: LivecastState? = null
            private set

        @Volatile var serverRef: LivecastServer? = null
            private set

        /** Called by the service to publish its singletons to the UI. */
        fun publish(state: LivecastState, server: LivecastServer?) {
            stateRef = state
            serverRef = server
        }
    }
}
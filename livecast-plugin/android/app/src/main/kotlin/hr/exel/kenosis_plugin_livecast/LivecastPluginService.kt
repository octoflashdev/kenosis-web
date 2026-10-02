package hr.exel.kenosis_plugin_livecast

import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.util.Log
import hr.exel.kenosis.plugin.IKenosisPlugin
import org.json.JSONArray
import org.json.JSONObject

/**
 * The LiveCast plugin service: bound by the offline Kenosis host over binder
 * (AIDL `IKenosisPlugin`, contract file copied into both apps). Serves the
 * realtime-lecture-transcription page to any device on the same Wi-Fi.
 *
 * Unlike the Internet Search plugin this app does NOT talk to the public
 * internet at all — its INTERNET permission exists only because Android
 * requires it for a listening TCP socket (the NanoHTTPD LAN server), and the
 * CI permission gate requires every plugin app to declare it (the architecture decision record).
 *
 * Tools (host-internal — the LLM never sees these; the host's chat tool
 * round only surfaces the Internet Search plugin's manifest):
 *  - livecast_status: {serverRunning, port, sessionEpoch, sessionElapsedMs,
 *    segments, digests} — the host builds its QR/LAN URL from `port`.
 *  - livecast_reset: fresh session (clears segments/digests, bumps epoch).
 *  - livecast_push: segments:[{seq,startMs,endMs,text}] + sessionElapsedMs →
 *    appends to the shared state (idempotent below lastSeq).
 *  - livecast_push_digest: {index,text,fromMs,toMs} → appends a digest card.
 *
 * Server lifecycle: NanoHTTPD starts in onCreate (the service is created on
 * first bind and dies when the host unbinds), stops in onDestroy. If no port
 * of the 8090..8099 ladder is free, the server stays down and every
 * livecast_status reports serverRunning:false — the session itself is never
 * blocked by a missing page.
 */
class LivecastPluginService : Service() {

    companion object {
        const val TAG = "LivecastPlugin"

        /** Same action the host's manifest <queries> declares — discovery is
         *  action-based, so the `.debug` package suffix is invisible. */
        const val PLUGIN_SERVICE_ACTION = "hr.exel.kenosis_ai.PLUGIN_SERVICE"

        /** The 4 tool names the host's LiveCastRepositoryImpl verifies in the
         *  manifest after attach (all-or-nothing: a manifest missing any of
         *  them means a stale plugin install). */
        val REQUIRED_TOOLS = listOf(
            "livecast_status",
            "livecast_reset",
            "livecast_push",
            "livecast_push_digest",
        )
    }

    private val state = LivecastState()
    private var server: LivecastServer? = null

    override fun onCreate() {
        super.onCreate()
        server = LivecastServer(this, state)
        try {
            server?.startWithRetry()
        } catch (e: Exception) {
            // The page is an affordance, not the session — keep the plugin
            // usable (status/reset/push all still work) without a server.
            Log.w(TAG, "FC: [LivecastPlugin] web server failed to start: $e")
            server = null
        }
        // Publish to the same-process launcher screen (MainActivity reads the
        // live state over the kenosis_livecast/ui channel).
        MainActivity.publish(state, server)
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onDestroy() {
        server?.stopServer()
        server = null
        MainActivity.publish(state, null)
        Log.i(TAG, "FC: [LivecastPlugin] service destroyed")
        super.onDestroy()
    }

    private val binder = object : IKenosisPlugin.Stub() {

        override fun getManifest(): String {
            // Built in Kotlin (not a string resource) — ONE representation of
            // the tool list; the host parses it with jsonDecode.
            return """
                {
                  "name": "LiveCast",
                  "version": "0.1.0",
                  "tools": [
                    {
                      "name": "livecast_status",
                      "description": "Returns the LiveCast server state: serverRunning, port, sessionEpoch, sessionElapsedMs, segment and digest counts.",
                      "parameters": {}
                    },
                    {
                      "name": "livecast_reset",
                      "description": "Starts a fresh LiveCast session on the consumer side: clears all segments and digests so the projector page renders clean.",
                      "parameters": {}
                    },
                    {
                      "name": "livecast_push",
                      "description": "Appends realtime transcript segments to the LiveCast session.",
                      "parameters": {
                        "segments": {
                          "type": "array",
                          "description": "New segments [{seq,startMs,endMs,text}] — seq is the host-assigned monotonic cursor."
                        },
                        "sessionElapsedMs": {
                          "type": "number",
                          "description": "Host session-relative elapsed ms (audio-anchored)."
                        }
                      }
                    },
                    {
                      "name": "livecast_push_digest",
                      "description": "Appends a periodic digest card to the LiveCast session.",
                      "parameters": {
                        "index": {
                          "type": "number",
                          "description": "Monotonic digest index (0, 1, 2, …) — one per 5-minute window."
                        },
                        "text": {
                          "type": "string",
                          "description": "The digest body."
                        },
                        "fromMs": {
                          "type": "number",
                          "description": "Session-relative start of the digest span."
                        },
                        "toMs": {
                          "type": "number",
                          "description": "Session-relative end of the digest span."
                        }
                      }
                    }
                  ]
                }
            """.trimIndent()
        }

        override fun invoke(toolName: String, paramsJson: String): String {
            Log.i(TAG, "FC: [LivecastPlugin] invoke($toolName) params=$paramsJson")
            return when (toolName) {
                "livecast_status" -> invokeStatus()
                "livecast_reset" -> invokeReset()
                "livecast_push" -> invokePush(paramsJson)
                "livecast_push_digest" -> invokePushDigest(paramsJson)
                else -> state.err("Unknown tool: $toolName")
            }
        }
    }

    private fun invokeStatus(): String {
        val s = server
        val running = s != null && s.boundPort > 0
        val port = s?.boundPort ?: -1
        return state.statusJson(serverRunning = running, port = port).toString()
    }

    private fun invokeReset(): String {
        Log.i(TAG, "FC: [LivecastPlugin] reset → epoch bump")
        return state.reset().toString()
    }

    /** livecast_push: validates each segment (malformed entries are dropped,
     *  not fatal — the session keeps flowing) and appends the rest. */
    private fun invokePush(paramsJson: String): String {
        val params = try {
            JSONObject(paramsJson)
        } catch (e: Exception) {
            Log.w(TAG, "FC: [LivecastPlugin] livecast_push: bad params JSON: $e")
            return state.err("Parameters are not valid JSON.")
        }
        val raw = params.optJSONArray("segments")
            ?: return state.err("Missing required parameter: segments")
        val parsed = ArrayList<LivecastState.Segment>(raw.length())
        for (i in 0 until raw.length()) {
            LivecastState.parseSegment(raw.opt(i))?.let { parsed.add(it) }
        }
        val elapsed = params.optLong("sessionElapsedMs", 0L)
        return state.push(parsed, elapsed).toString()
    }

    /** livecast_push_digest: {index,text,fromMs,toMs}. */
    private fun invokePushDigest(paramsJson: String): String {
        val params = try {
            JSONObject(paramsJson)
        } catch (e: Exception) {
            Log.w(TAG, "FC: [LivecastPlugin] livecast_push_digest: bad params JSON: $e")
            return state.err("Parameters are not valid JSON.")
        }
        val index = params.optInt("index", -1)
        if (index < 0) return state.err("Missing required parameter: index")
        val text = params.optString("text")
        if (text.isBlank()) return state.err("Missing required parameter: text")
        val d = LivecastState.Digest(
            index = index,
            text = text,
            fromMs = params.optLong("fromMs", 0L),
            toMs = params.optLong("toMs", 0L),
        )
        return state.pushDigest(d).toString()
    }
}
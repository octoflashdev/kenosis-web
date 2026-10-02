package hr.exel.kenosis_plugin_livecast

import android.content.Context
import android.util.Log
import fi.iki.elonen.NanoHTTPD
import fi.iki.elonen.NanoHTTPD.IHTTPSession
import fi.iki.elonen.NanoHTTPD.Response
import fi.iki.elonen.NanoHTTPD.newChunkedResponse
import fi.iki.elonen.NanoHTTPD.newFixedLengthResponse
import java.io.IOException
import java.net.BindException

/**
 * The LiveCast web server: serves the projector page (`GET /` → the bundled
 * `assets/livecast/index.html`) and the polling delta (`GET /state?since=…&digestsSince=…`)
 * over the LAN so any device on the same Wi-Fi can follow the live transcript.
 *
 * Port ladder: starts on 8090, retries +1 up to +9 on [BindException] (another
 * app squatting the port). The ACTUAL bound port is what `livecast_status`
 * reports — the host builds the QR/LAN URL from it, so the retry is invisible.
 *
 * Fully LAN-local: no TLS, no auth — the page is read-only transcript state,
 * and the same tradeoff the whole debug feature surface makes. The service
 * owns the lifecycle: started in LivecastPluginService.onCreate, stopped in
 * onDestroy (the host unbinds when the session ends).
 */
class LivecastServer(context: Context, private val state: LivecastState) {

    companion object {
        const val TAG = "LivecastServer"
        const val DEFAULT_PORT = 8090
        const val PORT_RETRY_MAX = 9 // 8090..8099

        /** The page asset served on GET /. Kept in the Flutter asset bundle so
         *  it rides the APK like any other asset (pubspec `assets:`). */
        const val PAGE_ASSET = "livecast/index.html"
    }

    private val assets = context.assets

    /** The port the server actually bound (set by [startWithRetry]; -1 while
     *  stopped). The host reads it via livecast_status. */
    var boundPort: Int = -1
        private set

    /** Starts on the first free port of the ladder. Returns the bound port.
     *  Throws only when every port of the ladder is taken. */
    @Throws(IOException::class)
    fun startWithRetry(): Int {
        var lastError: IOException? = null
        for (offset in 0..PORT_RETRY_MAX) {
            val port = DEFAULT_PORT + offset
            // Re-create the socket-less NanoHTTPD state per attempt: the
            // hostname/port fields are final in the base class, so a fresh
            // instance is bound per port and only the winner is kept alive.
            val server = LivecastServerInstance(port)
            try {
                server.start(NanoHTTPD.SOCKET_READ_TIMEOUT, false)
                boundPort = port
                _instance = server
                Log.i(TAG, "FC: [LivecastPlugin] server up on :$port")
                return port
            } catch (e: BindException) {
                lastError = e
                Log.w(TAG, "FC: [LivecastPlugin] port $port taken — trying next")
                server.stop()
            } catch (e: IOException) {
                // NanoHTTPD wraps bind failures in plain IOException on some
                // platforms — treat any bind-time IOException as a retry.
                lastError = e
                Log.w(TAG, "FC: [LivecastPlugin] port $port failed: $e — trying next")
                server.stop()
            }
        }
        throw lastError ?: IOException("No port free in 8090..${DEFAULT_PORT + PORT_RETRY_MAX}")
    }

    /** The winning inner instance (null until [startWithRetry] succeeds). */
    private var _instance: LivecastServerInstance? = null

    /** Stops the bound instance (idempotent — safe from onDestroy). */
    fun stopServer() {
        _instance?.stop()
        _instance = null
        boundPort = -1
        Log.i(TAG, "FC: [LivecastPlugin] server stopped")
    }

    /** Inner NanoHTTPD carrying the actual port — the outer class exists so
     *  the service talks to ONE object across the retry ladder. */
    private inner class LivecastServerInstance(port: Int) : NanoHTTPD(port) {
        override fun serve(session: IHTTPSession): Response {
            val uri = session.uri ?: "/"
            return when {
                uri == "/" || uri == "/index.html" -> servePage()
                uri == "/state" -> serveState(session)
                else -> newFixedLengthResponse(
                    Response.Status.NOT_FOUND, "text/plain", "not found\n",
                )
            }
        }
    }

    /** GET / — the self-contained projector page (no CDN: the laptop may be
     *  offline; everything is inline in the one HTML file). The page ships as
     *  a FLUTTER asset (pubspec `assets:`), which the APK stores under
     *  `flutter_assets/` — try that first, fall back to the bare Android
     *  asset path. */
    private fun servePage(): Response {
        val streams = sequenceOf("flutter_assets/assets/$PAGE_ASSET", PAGE_ASSET)
            .mapNotNull { path ->
                try {
                    assets.open(path)
                } catch (e: IOException) {
                    Log.i(TAG, "FC: [LivecastPlugin] no asset at $path")
                    null
                }
            }
        for (stream in streams) {
            return stream.use {
                newChunkedResponse(
                    Response.Status.OK, "text/html; charset=utf-8", it.readBytes().inputStream(),
                )
            }
        }
        Log.e(TAG, "FC: [LivecastPlugin] page asset missing: $PAGE_ASSET")
        return newFixedLengthResponse(
            Response.Status.INTERNAL_ERROR, "text/plain", "page asset missing\n",
        )
    }

    /** GET /state?since=<lastSeq>&digestsSince=<count> — the polling delta. */
    private fun serveState(session: IHTTPSession): Response {
        val since = session.parameters["since"]?.firstOrNull()?.toLongOrNull() ?: -1L
        val digestsSince = session.parameters["digestsSince"]?.firstOrNull()?.toIntOrNull() ?: 0
        val json = state.stateJson(since, digestsSince)
        return newFixedLengthResponse(
            Response.Status.OK, "application/json", json.toString(),
        )
    }
}
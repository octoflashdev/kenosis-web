package hr.exel.kenosis_plugin_livecast

import org.json.JSONArray
import org.json.JSONObject

/**
 * Pure, unit-testable session state for the LiveCast plugin app.
 *
 * The host (offline Kenosis app) pushes realtime transcript segments and
 * periodic digests over binder (`livecast_push` / `livecast_push_digest`);
 * this class is the single in-memory store those pushes land in, and the
 * only source the HTTP server reads. Everything is synchronized because
 * binder invocations arrive on the binder thread pool while NanoHTTPD reads
 * on its own client threads.
 *
 * Cursors: segments are append-only and numbered by the HOST (monotonic
 * `seq` starting at 0 each session). The web page polls
 * `/state?since=<lastSeq>&digestsSince=<count>` and receives only the delta;
 * [push] ignores any segment at or below the last accepted seq so a
 * re-attached host's catch-up push is idempotent.
 *
 * Memory bound: the segment ring is capped at [MAX_SEGMENTS] (~2 MB of
 * text) with drop-oldest trimming. When trimming has actually dropped
 * anything, [stateJson] reports `firstSeq > 0` + `trimmed:true` so the page
 * can detect the seq discontinuity, reset its DOM, and show the
 * "history trimmed" banner (the page keeps `since` monotonic — a gap is the
 * reset signal, not an error).
 */
class LivecastState {

    data class Segment(val seq: Long, val startMs: Long, val endMs: Long, val text: String)

    data class Digest(val index: Int, val text: String, val fromMs: Long, val toMs: Long)

    companion object {
        /** Segment ring cap: ~2000 segments × ~1 KB ≈ 2 MB (a 2 h session). */
        const val MAX_SEGMENTS = 2000

        /** Digest list cap — 5-min digests over a 2 h session is only 24; the
         *  cap exists so a runaway scheduler can't grow the list unbounded. */
        const val MAX_DIGESTS = 100

        /** Pure: builds one segment JSON object from its parts. */
        fun segmentJson(seq: Long, startMs: Long, endMs: Long, text: String): JSONObject =
            JSONObject()
                .put("seq", seq)
                .put("startMs", startMs)
                .put("endMs", endMs)
                .put("text", text)

        /** Pure: validates one pushed-segment entry — null when malformed
         *  (missing seq/startMs/endMs or blank text). Accepts BOTH a
         *  [JSONObject] (what the service hands over after parsing the
         *  invoke params) and a plain [Map] (unit tests). Kept pure so the
         *  boundary behavior is unit-testable without Android. */
        fun parseSegment(m: Any?): Segment? {
            val seq: Long
            val startMs: Long
            val endMs: Long
            val text: String
            when (m) {
                is JSONObject -> {
                    if (!m.has("seq") || !m.has("startMs") ||
                        !m.has("endMs") || !m.has("text")) return null
                    seq = m.optLong("seq")
                    startMs = m.optLong("startMs")
                    endMs = m.optLong("endMs")
                    text = m.optString("text")
                }
                is Map<*, *> -> {
                    seq = (m["seq"] as? Number)?.toLong() ?: return null
                    startMs = (m["startMs"] as? Number)?.toLong() ?: return null
                    endMs = (m["endMs"] as? Number)?.toLong() ?: return null
                    text = m["text"] as? String ?: return null
                }
                else -> return null
            }
            if (text.isBlank()) return null
            return Segment(seq, startMs, endMs, text)
        }
    }

    private val segments = ArrayList<Segment>()
    private val digests = ArrayList<Digest>()

    /** Bumped on every [reset] — the page polls the epoch and full-resets its
     *  DOM when it changes (a new session started on the host). */
    var sessionEpoch: Long = 0
        private set

    /** Session-relative ms the page's elapsed clock runs on (audio-anchored:
     *  the host reports the max segment endMs it has seen). */
    var sessionElapsedMs: Long = 0
        private set

    /** The last accepted host-assigned seq (−1 when no segment yet). */
    var lastSeq: Long = -1
        private set

    /** The seq of the OLDEST retained segment (gap marker after trimming). */
    var firstSeq: Long = 0
        private set

    @get:Synchronized val segmentCount: Int get() = segments.size
    @get:Synchronized val digestCount: Int get() = digests.size

    /** Starts a fresh session: clears everything, bumps the epoch so every
     *  connected page resets its DOM. Returns the `{"ok":…}` envelope. */
    @Synchronized
    fun reset(): JSONObject {
        segments.clear()
        digests.clear()
        sessionEpoch += 1
        sessionElapsedMs = 0
        lastSeq = -1
        firstSeq = 0
        Log_i("reset → epoch=$sessionEpoch")
        return ok(
            JSONObject()
                .put("sessionEpoch", sessionEpoch)
                .put("segmentCount", 0)
                .put("digestCount", 0),
        )
    }

    /**
     * Appends host-pushed segments. Segments at or below [lastSeq] are
     * ignored (idempotent catch-up after a rebind); the rest are appended in
     * order, the ring is trimmed drop-oldest over [MAX_SEGMENTS], and
     * [sessionElapsedMs] advances to the max seen. Returns the envelope.
     */
    @Synchronized
    fun push(incoming: List<Segment>, elapsedMs: Long): JSONObject {
        var accepted = 0
        for (s in incoming) {
            if (s.seq <= lastSeq) continue
            segments.add(s)
            lastSeq = s.seq
            accepted++
        }
        while (segments.size > MAX_SEGMENTS) {
            segments.removeAt(0)
            firstSeq = segments.first().seq
        }
        if (elapsedMs > sessionElapsedMs) sessionElapsedMs = elapsedMs
        Log_i("push accepted=$accepted size=${segments.size} lastSeq=$lastSeq")
        return ok(
            JSONObject()
                .put("lastSeq", lastSeq)
                .put("segmentCount", segments.size)
                .put("digestCount", digests.size),
        )
    }

    /** Appends one digest card (Phase 3). Re-pushing an index the store
     *  already holds is a no-op (one-shot retry path). */
    @Synchronized
    fun pushDigest(d: Digest): JSONObject {
        if (digests.none { it.index == d.index }) {
            digests.add(d)
            digests.sortBy { it.index }
            while (digests.size > MAX_DIGESTS) digests.removeAt(0)
        }
        Log_i("pushDigest index=${d.index} size=${digests.size}")
        return ok(
            JSONObject()
                .put("index", d.index)
                .put("digestCount", digests.size),
        )
    }

    /** The plugin status the HOST asks for via `livecast_status`: server +
     *  counts + session clock. The port is injected by the service (the
     *  server's actual bound port after the retry ladder). */
    @Synchronized
    fun statusJson(serverRunning: Boolean, port: Int): JSONObject =
        ok(
            JSONObject()
                .put("serverRunning", serverRunning)
                .put("port", port)
                .put("sessionEpoch", sessionEpoch)
                .put("sessionElapsedMs", sessionElapsedMs)
                .put("segments", segments.size)
                .put("digests", digests.size),
        )

    /**
     * The polling delta for the web page: segments with `seq > since`,
     * digests with `index >= digestsSince`, plus the epoch/firstSeq markers
     * the page's reset + gap detection need. Full-shape envelope — the page
     * resets on an epoch change and on `firstSeq > since` (history it asked
     * for is gone).
     */
    @Synchronized
    fun stateJson(since: Long, digestsSince: Int): JSONObject {
        val segArr = JSONArray()
        for (s in segments) {
            if (s.seq > since) {
                segArr.put(segmentJson(s.seq, s.startMs, s.endMs, s.text))
            }
        }
        val digArr = JSONArray()
        for (d in digests) {
            if (d.index >= digestsSince) {
                digArr.put(
                    JSONObject()
                        .put("index", d.index)
                        .put("text", d.text)
                        .put("fromMs", d.fromMs)
                        .put("toMs", d.toMs),
                )
            }
        }
        val trimmed = firstSeq > 0
        return ok(
            JSONObject()
                .put("epoch", sessionEpoch)
                .put("sessionElapsedMs", sessionElapsedMs)
                .put("lastSeq", lastSeq)
                .put("firstSeq", firstSeq)
                .put("trimmed", trimmed)
                .put("digestsTrimmed", digArr.length() < digests.size && digestsSince > 0)
                .put("segments", segArr)
                .put("digests", digArr),
        )
    }

    /** The one error envelope shape shared by every tool. */
    fun err(message: String): String =
        JSONObject().put("ok", false).put("error", message).toString()

    private fun ok(data: JSONObject): JSONObject =
        JSONObject().put("ok", true).put("data", data)

    // Thin indirection over android.util.Log so the JUnit tests (no Android
    // runtime) can construct the class without a "not mocked" stub blowup.
    private fun Log_i(msg: String) {
        try {
            android.util.Log.i("LivecastState", "FC: [LivecastPlugin] state: $msg")
        } catch (_: Exception) {
            // unit-test runtime: android.jar stubs throw — swallow.
        }
    }
}
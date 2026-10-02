package hr.exel.kenosis_plugin_livecast

import org.json.JSONArray
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Pure state-machine tests for [LivecastState] (no Android runtime needed —
 * run on the dev machine:
 * `cd plugins/livecast/android && ./gradlew :app:testDebugUnitTest`,
 * NOT on the build server — same policy as the host app's tests).
 */
class LivecastStateTest {

    private fun seg(seq: Long, startMs: Long = seq * 5000, endMs: Long = startMs + 5000, text: String = "seg $seq") =
        LivecastState.Segment(seq, startMs, endMs, text)

    // ------------------------------------------------------------------ //
    // reset / epoch                                                      //
    // ------------------------------------------------------------------ //

    @Test
    fun resetClearsStateAndBumpsEpoch() {
        val s = LivecastState()
        s.push(listOf(seg(0), seg(1)), elapsedMs = 10_000)
        s.pushDigest(LivecastState.Digest(0, "d", 0, 300_000))
        assertEquals(2, s.segmentCount)
        assertEquals(1, s.digestCount)

        val before = s.sessionEpoch
        val envelope = s.reset()
        val data = envelope.getJSONObject("data")
        assertTrue(envelope.getBoolean("ok"))
        assertEquals(before + 1, s.sessionEpoch)
        assertEquals(0, s.segmentCount)
        assertEquals(0, s.digestCount)
        assertEquals(0, data.getInt("digestCount"))
        assertEquals(-1L, s.lastSeq)
        assertEquals(0L, s.firstSeq)
        assertEquals(0L, s.sessionElapsedMs)
    }

    @Test
    fun resetEnvelopeCarriesNewEpoch() {
        val s = LivecastState()
        val e1 = s.reset().getJSONObject("data").getLong("sessionEpoch")
        val e2 = s.reset().getJSONObject("data").getLong("sessionEpoch")
        assertEquals(e1 + 1, e2)
    }

    // ------------------------------------------------------------------ //
    // push: append, idempotence, ring cap, elapsed                       //
    // ------------------------------------------------------------------ //

    @Test
    fun pushAppendsNewSegmentsAndReportsCounts() {
        val s = LivecastState()
        val r = s.push(listOf(seg(0), seg(1), seg(2)), elapsedMs = 15_000)
        val data = r.getJSONObject("data")
        assertTrue(r.getBoolean("ok"))
        assertEquals(2, data.getLong("lastSeq"))
        assertEquals(3, data.getInt("segmentCount"))
        assertEquals(0, data.getInt("digestCount"))
        assertEquals(3, s.segmentCount)
    }

    @Test
    fun pushIgnoresSegmentsAtOrBelowLastSeq() {
        // Idempotent catch-up: after a rebind the host re-pushes everything
        // it has; the store must accept only the strictly-new tail.
        val s = LivecastState()
        s.push(listOf(seg(0), seg(1)), elapsedMs = 10_000)
        val r = s.push(listOf(seg(0), seg(1), seg(2)), elapsedMs = 15_000)
        assertEquals(2, r.getJSONObject("data").getLong("lastSeq"))
        assertEquals(3, s.segmentCount)
    }

    @Test
    fun pushTrimsDropOldestOverCapAndAdvancesFirstSeq() {
        val s = LivecastState()
        val many = (0 until (LivecastState.MAX_SEGMENTS + 50).toLong()).map { seg(it) }
        s.push(many, elapsedMs = 0)
        assertEquals(LivecastState.MAX_SEGMENTS, s.segmentCount)
        // Oldest dropped → firstSeq advanced off 0 (the page's gap marker).
        assertTrue(s.firstSeq > 0)
        // The newest segment survived the trim (seqs ran 0..MAX+49).
        assertEquals((LivecastState.MAX_SEGMENTS + 49).toLong(), s.lastSeq)
    }

    @Test
    fun pushAdvancesSessionElapsedOnlyForward() {
        val s = LivecastState()
        s.push(listOf(seg(0)), elapsedMs = 60_000)
        s.push(emptyList(), elapsedMs = 30_000) // older — ignored
        assertEquals(60_000, s.sessionElapsedMs)
        s.push(listOf(seg(1)), elapsedMs = 120_000)
        assertEquals(120_000, s.sessionElapsedMs)
    }

    // ------------------------------------------------------------------ //
    // pushDigest                                                         //
    // ------------------------------------------------------------------ //

    @Test
    fun pushDigestAppendsAndDedupsByIndex() {
        val s = LivecastState()
        s.pushDigest(LivecastState.Digest(0, "one", 0, 300_000))
        val r = s.pushDigest(LivecastState.Digest(0, "one again", 0, 300_000))
        assertEquals(1, s.digestCount)
        assertEquals(1, r.getJSONObject("data").getInt("digestCount"))

        s.pushDigest(LivecastState.Digest(1, "two", 300_000, 600_000))
        assertEquals(2, s.digestCount)
    }

    @Test
    fun pushDigestKeepsIndexOrderUnderOutOfOrderArrival() {
        val s = LivecastState()
        s.pushDigest(LivecastState.Digest(1, "second", 300_000, 600_000))
        s.pushDigest(LivecastState.Digest(0, "first", 0, 300_000))
        val delta = s.stateJson(since = -1, digestsSince = 0)
            .getJSONObject("data").getJSONArray("digests")
        assertEquals(0, delta.getJSONObject(0).getInt("index"))
        assertEquals(1, delta.getJSONObject(1).getInt("index"))
    }

    // ------------------------------------------------------------------ //
    // stateJson: polling delta                                           //
    // ------------------------------------------------------------------ //

    @Test
    fun stateJsonReturnsOnlySegmentsAfterSince() {
        val s = LivecastState()
        s.push(listOf(seg(0), seg(1), seg(2)), elapsedMs = 15_000)

        val delta = s.stateJson(since = 1, digestsSince = 0).getJSONObject("data")
        val segs = delta.getJSONArray("segments")
        assertEquals(1, segs.length())
        assertEquals(2, segs.getJSONObject(0).getLong("seq"))
        assertEquals(2, delta.getLong("lastSeq"))
        assertFalse(delta.getBoolean("trimmed"))
    }

    @Test
    fun stateJsonFullReplayFromSinceMinusOne() {
        // Page (re)load: since=-1 → everything retained.
        val s = LivecastState()
        s.push(listOf(seg(0), seg(1)), elapsedMs = 10_000)
        s.pushDigest(LivecastState.Digest(0, "d", 0, 300_000))
        val delta = s.stateJson(since = -1, digestsSince = 0).getJSONObject("data")
        assertEquals(2, delta.getJSONArray("segments").length())
        assertEquals(1, delta.getJSONArray("digests").length())
        assertEquals(0, delta.getLong("firstSeq"))
    }

    @Test
    fun stateJsonReportsTrimmedWhenHistoryWasDropped() {
        val s = LivecastState()
        val many = (0 until (LivecastState.MAX_SEGMENTS + 10).toLong()).map { seg(it) }
        s.push(many, elapsedMs = 0)
        val delta = s.stateJson(since = -1, digestsSince = 0).getJSONObject("data")
        assertTrue(delta.getBoolean("trimmed"))
        assertTrue(delta.getLong("firstSeq") > 0)
        // A page that had since=0 gets a discontinuity signal: the first
        // returned seq is > since.
        assertTrue(delta.getJSONArray("segments").getJSONObject(0).getLong("seq") > 0)
    }

    @Test
    fun stateJsonCarriesEpochForPageResetDetection() {
        val s = LivecastState()
        s.reset()
        val epoch = s.sessionEpoch
        val delta = s.stateJson(since = -1, digestsSince = 0).getJSONObject("data")
        assertEquals(epoch, delta.getLong("epoch"))
    }

    @Test
    fun stateJsonReturnsOnlyDigestsFromDigestsSince() {
        val s = LivecastState()
        for (i in 0 until 3) {
            s.pushDigest(LivecastState.Digest(i, "d$i", i * 300_000L, (i + 1) * 300_000L))
        }
        val delta = s.stateJson(since = -1, digestsSince = 1).getJSONObject("data")
        val digests = delta.getJSONArray("digests")
        assertEquals(2, digests.length())
        assertEquals(1, digests.getJSONObject(0).getInt("index"))
        assertEquals(2, digests.getJSONObject(1).getInt("index"))
    }

    // ------------------------------------------------------------------ //
    // statusJson                                                         //
    // ------------------------------------------------------------------ //

    @Test
    fun statusJsonCarriesServerPortAndCounts() {
        val s = LivecastState()
        s.push(listOf(seg(0), seg(1)), elapsedMs = 10_000)
        s.pushDigest(LivecastState.Digest(0, "d", 0, 300_000))
        val data = s.statusJson(serverRunning = true, port = 8090)
            .getJSONObject("data")
        assertTrue(data.getBoolean("serverRunning"))
        assertEquals(8090, data.getInt("port"))
        assertEquals(2, data.getInt("segments"))
        assertEquals(1, data.getInt("digests"))
        assertEquals(10_000, data.getLong("sessionElapsedMs"))
    }

    // ------------------------------------------------------------------ //
    // parseSegment boundary                                              //
    // ------------------------------------------------------------------ //

    @Test
    fun parseSegmentRejectsMalformedEntries() {
        val good = mapOf("seq" to 3L, "startMs" to 1L, "endMs" to 2L, "text" to "hi")
        assertEquals(3, LivecastState.parseSegment(good)!!.seq)

        // Every malformed shape → null (dropped, not fatal).
        assertNull(LivecastState.parseSegment(null))
        assertNull(LivecastState.parseSegment("not a map"))
        assertNull(LivecastState.parseSegment(mapOf("startMs" to 1L, "endMs" to 2L, "text" to "x"))) // no seq
        assertNull(LivecastState.parseSegment(mapOf("seq" to 3L, "endMs" to 2L, "text" to "x"))) // no startMs
        assertNull(LivecastState.parseSegment(mapOf("seq" to 3L, "startMs" to 1L, "text" to "x"))) // no endMs
        assertNull(LivecastState.parseSegment(mapOf("seq" to 3L, "startMs" to 1L, "endMs" to 2L))) // no text
        assertNull(LivecastState.parseSegment(mapOf("seq" to 3L, "startMs" to 1L, "endMs" to 2L, "text" to "  ")))
    }

    @Test
    fun parseSegmentAcceptsJsonObjectShape() {
        // The SERVICE path: invoke params parse into JSONObjects — the shape
        // raw.optJSONArray("segments").opt(i) actually produces. A plain-map
        // -only validator silently drops every real segment.
        val good = org.json.JSONObject("{\"seq\":7,\"startMs\":1000,\"endMs\":6000,\"text\":\" hi\"}")
        val seg = LivecastState.parseSegment(good)
        assertEquals(7L, seg!!.seq)
        assertEquals(1000L, seg.startMs)
        assertEquals(6000L, seg.endMs)
        assertEquals(" hi", seg.text)

        // Malformed JSONObject shapes → null too.
        assertNull(LivecastState.parseSegment(org.json.JSONObject("{\"startMs\":1,\"endMs\":2,\"text\":\"x\"}"))) // no seq
        assertNull(LivecastState.parseSegment(org.json.JSONObject("{\"seq\":1,\"startMs\":1,\"endMs\":2}"))) // no text
        assertNull(LivecastState.parseSegment(org.json.JSONObject("{\"seq\":1,\"startMs\":1,\"endMs\":2,\"text\":\"  \"}"))) // blank
        assertNull(LivecastState.parseSegment(org.json.JSONArray().opt(0))) // not an object
    }

    // ------------------------------------------------------------------ //
    // error envelope                                                     //
    // ------------------------------------------------------------------ //

    @Test
    fun errEnvelopeShape() {
        val s = LivecastState()
        val raw = s.err("Missing required parameter: index")
        val json = org.json.JSONObject(raw)
        assertFalse(json.getBoolean("ok"))
        assertEquals("Missing required parameter: index", json.getString("error"))
    }

    private fun assertNull(actual: Any?) {
        assertTrue("expected null", actual == null)
    }
}
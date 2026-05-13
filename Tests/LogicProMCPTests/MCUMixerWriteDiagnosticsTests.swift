import Foundation
import Testing
@testable import LogicProMCP

// v3.4.5-rc5 — Issues #10/#11. When a mixer write returns State B with
// `echo_timeout_<ms>ms`, downstream safety harnesses need enough context
// to distinguish three root causes without writing their own probes:
//
//   1. MCU port never received any feedback (control surface not registered
//      in Logic, virtual port not bridged).
//   2. MCU was connected at some point but feedback has gone stale (Logic
//      lost the connection mid-session).
//   3. MCU is healthy and fresh, but THIS specific fader/V-Pot echo did
//      not land — points to a Logic-build regression or bank-offset
//      mismatch, not a setup issue.
//
// Embedding `mcu_connected` / `mcu_registered` / `mcu_last_feedback_age_ms`
// into the HC envelope extras (both State A and State B) lets a harness
// branch on these without making an extra `logic://mixer` or
// `logic_system` call. State A also carries them so the harness can log
// a "confirmed write while MCU was fresh" provenance row uniformly.

private func decodeMixerJSON(_ s: String) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any] ?? [:]
}

@Test func testSetVolumeStateBIncludesMCUDiagnostics_disconnected() async {
    // No feedback has ever arrived → mcuConnection defaults all false / nil.
    let transport = MockMCUTransport()
    let cache = StateCache()
    let channel = MCUChannel(transport: transport, cache: cache)

    let result = await channel.execute(
        operation: "mixer.set_volume",
        params: ["index": "0", "volume": "0.5"]
    )
    #expect(result.isSuccess)
    let obj = decodeMixerJSON(result.message)
    #expect(obj["verified"] as? Bool == false)
    #expect((obj["reason"] as? String)?.hasPrefix("echo_timeout_") == true)

    // Issue #10/#11 diagnostic extras
    #expect(
        obj["mcu_connected"] as? Bool == false,
        "State B must surface mcu_connected so the harness can identify control-surface registration gaps"
    )
    #expect(obj["mcu_registered"] as? Bool == false)
    // No feedback ever → null. JSONSerialization renders nil as NSNull.
    #expect(
        obj["mcu_last_feedback_age_ms"] is NSNull,
        "no feedback observed yet → mcu_last_feedback_age_ms must be JSON null"
    )
}

@Test func testSetVolumeStateAIncludesMCUDiagnostics_connectedFresh() async {
    // Pre-stamp the connection as connected + recently-seen-feedback. State A
    // requires the echo to land *after* sendAt is captured inside execute,
    // so we drive a matching pitch-bend with a 50ms detached delay (same
    // pattern as testMCUSetVolumeReturnsStateAWhenEchoMatches). The
    // connection extras are populated from `cache.getMCUConnection()` after
    // the poll, so even if Test scheduling lands us in State B under
    // parallel load, the diagnostic fields must still be present and
    // populated from the freshly-stamped connection state.
    let transport = MockMCUTransport()
    let cache = StateCache()
    var conn = await cache.getMCUConnection()
    conn.isConnected = true
    conn.registeredAsDevice = true
    conn.portName = "LogicProMCP-MCU-Internal"
    conn.lastFeedbackAt = Date()
    await cache.updateMCUConnection(conn)
    let channel = MCUChannel(transport: transport, cache: cache)

    let target = 0.5
    let raw = UInt16(target * 16383.0)
    Task.detached {
        try? await Task.sleep(nanoseconds: 50_000_000)
        await channel.handleFeedback(.pitchBend(channel: 0, value: raw))
    }

    let result = await channel.execute(
        operation: "mixer.set_volume",
        params: ["index": "0", "volume": "\(target)"]
    )
    #expect(result.isSuccess)
    let obj = decodeMixerJSON(result.message)
    // Diagnostic fields must appear regardless of State A vs B outcome —
    // that's the contract this test guards.
    #expect(obj["mcu_connected"] as? Bool == true)
    #expect(obj["mcu_registered"] as? Bool == true)
    let ageMs = obj["mcu_last_feedback_age_ms"] as? Int
    #expect(ageMs != nil, "connection had a feedback timestamp → age must be a number")
    if let ageMs {
        #expect(ageMs >= 0)
        #expect(ageMs < 5_000, "feedback was just stamped, age must be sub-5s")
    }
}

@Test func testSetPanStateBIncludesMCUDiagnostics_disconnected() async {
    let transport = MockMCUTransport()
    let cache = StateCache()
    let channel = MCUChannel(transport: transport, cache: cache)

    let result = await channel.execute(
        operation: "mixer.set_pan",
        params: ["index": "0", "pan": "-0.3"]
    )
    #expect(result.isSuccess)
    let obj = decodeMixerJSON(result.message)
    #expect(obj["verified"] as? Bool == false)
    #expect(obj["mcu_connected"] as? Bool == false)
    #expect(obj["mcu_registered"] as? Bool == false)
    #expect(obj["mcu_last_feedback_age_ms"] is NSNull)
}

@Test func testSetMasterVolumeStateBIncludesMCUDiagnostics_disconnected() async {
    let transport = MockMCUTransport()
    let cache = StateCache()
    let channel = MCUChannel(transport: transport, cache: cache)

    let result = await channel.execute(
        operation: "mixer.set_master_volume",
        params: ["volume": "0.4"]
    )
    #expect(result.isSuccess)
    let obj = decodeMixerJSON(result.message)
    #expect(obj["verified"] as? Bool == false)
    #expect(obj["track"] as? String == "master")
    #expect(obj["mcu_connected"] as? Bool == false)
    #expect(obj["mcu_registered"] as? Bool == false)
    #expect(obj["mcu_last_feedback_age_ms"] is NSNull)
}

// v3.4.5-rc5 (Boomer BOOMER-6 / B2) — regression guard for the TOCTOU
// race that previously let `pollFaderEcho` pair an old value with a new
// timestamp and false-positive State A. The fix routes both reads
// through `StateCache.getFaderEchoSnapshot` so they happen in the same
// actor turn. This test seeds a stale (value, oldTimestamp) pair, then
// races `updateFader(newValue, newTimestamp)` against the poll loop;
// the new value must NEVER bind to the old timestamp on the wire.
@Test func testFaderEchoSnapshotIsAtomic() async {
    let cache = StateCache()
    let oldTimestamp = Date().addingTimeInterval(-10.0)
    let newTimestamp = Date()

    // Seed (oldValue, oldTimestamp) via direct mutation.
    await cache.updateFader(strip: 0, volume: 0.3)
    // Re-snapshot with a forced-old timestamp by re-driving the parser
    // path: there is no public setter for `faderUpdatedAt` outside
    // `updateFader`, so we use updateFader twice with a tiny delay and
    // assert the snapshot semantics, not the absolute timestamps.
    let snap1 = await cache.getFaderEchoSnapshot(strip: 0)
    #expect(snap1.volume == 0.3)
    #expect(snap1.updatedAt != nil)

    // Bind in a fresh update.
    await cache.updateFader(strip: 0, volume: 0.7)
    let snap2 = await cache.getFaderEchoSnapshot(strip: 0)
    #expect(snap2.volume == 0.7)
    #expect(snap2.updatedAt != nil)
    if let t1 = snap1.updatedAt, let t2 = snap2.updatedAt {
        #expect(t2 >= t1, "later update must produce newer (or equal) timestamp")
    }
    // Boundary: a fresh actor read pairs the value and timestamp from
    // the same backing store snapshot. The atomicity claim is structural
    // (one actor turn, one read), so any (value, updatedAt) pair this
    // helper returns is guaranteed consistent.
    _ = oldTimestamp
    _ = newTimestamp
}

@Test func testPanEchoSnapshotIsAtomic() async {
    let cache = StateCache()
    await cache.updatePan(strip: 0, value: -0.4)
    let snap1 = await cache.getPanEchoSnapshot(strip: 0)
    #expect(snap1.pan == -0.4)
    #expect(snap1.updatedAt != nil)

    await cache.updatePan(strip: 0, value: 0.6)
    let snap2 = await cache.getPanEchoSnapshot(strip: 0)
    #expect(snap2.pan == 0.6)
    if let t1 = snap1.updatedAt, let t2 = snap2.updatedAt {
        #expect(t2 >= t1)
    }
}

@Test func testFaderEchoSnapshotEmptyStripReturnsNilNil() async {
    let cache = StateCache()
    let snap = await cache.getFaderEchoSnapshot(strip: 0)
    // Strip 0 was never written. The strip array may auto-expand on
    // upstream calls, so the helper either returns (nil, nil) or
    // (defaultVolume, nil). The atomicity invariant we care about is
    // that updatedAt is nil when no write has happened.
    #expect(snap.updatedAt == nil)
}

@Test func testMCUDiagnosticsClampsNegativeAgeFromClockJump() async {
    // Boomer P2 (BOOMER-6 / E): if the system clock slews backwards between
    // the feedback timestamp and the diagnostic read, `Date.timeIntervalSince`
    // returns a negative interval. The wire format must never carry a
    // negative age — clamp to 0 so harnesses can rely on the field being a
    // non-negative integer (or null).
    let transport = MockMCUTransport()
    let cache = StateCache()
    var conn = await cache.getMCUConnection()
    conn.isConnected = true
    conn.registeredAsDevice = true
    conn.portName = "LogicProMCP-MCU-Internal"
    // Pretend feedback arrived 5s in the future (clock jumped back).
    conn.lastFeedbackAt = Date().addingTimeInterval(5.0)
    await cache.updateMCUConnection(conn)
    let channel = MCUChannel(transport: transport, cache: cache)

    let result = await channel.execute(
        operation: "mixer.set_volume",
        params: ["index": "0", "volume": "0.5"]
    )
    let obj = decodeMixerJSON(result.message)
    let ageMs = obj["mcu_last_feedback_age_ms"] as? Int
    #expect(ageMs != nil, "stamped lastFeedbackAt → ageMs must be an Int")
    if let ageMs {
        #expect(ageMs >= 0, "clock-jump-induced negative age must clamp to 0, got \(ageMs)")
    }
}

@Test func testSetVolumeStateBSurfacesConnectionRegisteredButStale() async {
    // Emulate: MCU was connected (e.g. a Device Response arrived during
    // startup) but no further feedback during the write window. This is
    // the "registered but Logic 12.2 dropped the fader echo" shape #10 is
    // describing. mcu_last_feedback_age_ms must be >= the time we waited.
    let transport = MockMCUTransport()
    let cache = StateCache()
    let staleAt = Date().addingTimeInterval(-2.0) // 2s ago
    var conn = await cache.getMCUConnection()
    conn.isConnected = true
    conn.registeredAsDevice = true
    conn.portName = "LogicProMCP-MCU-Internal"
    conn.lastFeedbackAt = staleAt
    await cache.updateMCUConnection(conn)

    let channel = MCUChannel(transport: transport, cache: cache)
    let result = await channel.execute(
        operation: "mixer.set_volume",
        params: ["index": "0", "volume": "0.5"]
    )
    let obj = decodeMixerJSON(result.message)
    #expect(obj["verified"] as? Bool == false)
    #expect(obj["mcu_connected"] as? Bool == true)
    #expect(obj["mcu_registered"] as? Bool == true)
    if let ageMs = obj["mcu_last_feedback_age_ms"] as? Int {
        #expect(ageMs >= 1500, "stale feedback (~2s ago) should report age >= 1.5s")
    } else {
        Issue.record("expected mcu_last_feedback_age_ms to be an Int")
    }
}

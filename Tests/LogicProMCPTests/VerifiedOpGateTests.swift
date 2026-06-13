import Foundation
import MCP
import Testing
@testable import LogicProMCP

// T3 — R14: verified mutating ops are serialized server-wide (one in flight).
// A second concurrent verified op is refused with State C verified_op_in_progress
// (safe_to_retry:true). get_inventory (read-only) is NOT gated.

@Test func testVerifiedOpGateSerializesAcquisition() async {
    let gate = VerifiedOpGate()
    #expect(await gate.tryAcquire() == true, "first acquire succeeds")
    #expect(await gate.tryAcquire() == false, "second acquire is refused while held")
    await gate.release()
    #expect(await gate.tryAcquire() == true, "acquire succeeds again after release")
    await gate.release()
}

@Test func testPluginsDispatcherRefusesConcurrentVerifiedOp() async {
    // Hold the shared gate, then issue a verified op through the dispatcher and
    // confirm it is refused with verified_op_in_progress before touching AX.
    // Release is awaited synchronously (NOT via defer { Task {} }) so the shared
    // singleton is clean before this test returns — otherwise a later test could
    // observe the gate still held by a not-yet-run release Task.
    let acquired = await VerifiedOpGate.shared.tryAcquire()
    #expect(acquired == true)

    let router = ChannelRouter()
    let result = await PluginsDispatcher.handle(
        command: "set_param_verified",
        params: [
            "track": .int(0), "insert": .int(2), "plugin": .string("Gain"),
            "param": .string("gain_db"), "value": .double(-4.0), "unit": .string("dB"),
            "mode": .string("duplicate_applyback"),
            "project_expected_path": .string("/tmp/x.logicx"),
        ],
        router: router,
        cache: StateCache()
    )
    await VerifiedOpGate.shared.release()

    let text = sharedToolText(result)
    let obj = try! JSONSerialization.jsonObject(with: text.data(using: .utf8)!) as! [String: Any]
    #expect(obj["error"] as? String == "verified_op_in_progress")
    #expect(obj["state"] as? String == "C")
    #expect(obj["safe_to_retry"] as? Bool == true)
    #expect(obj["write_attempted"] as? Bool == false)
}

@Test func testGetInventoryNotGatedByVerifiedOpLock() async {
    // Even while the verified-op gate is held, get_inventory (read-only) must
    // still run — it is not a mutating verified op.
    let acquired = await VerifiedOpGate.shared.tryAcquire()
    #expect(acquired == true)

    let router = ChannelRouter()
    let result = await PluginsDispatcher.handle(
        command: "get_inventory",
        params: ["track": .int(0)],
        router: router,
        cache: StateCache()
    )
    await VerifiedOpGate.shared.release()

    let text = sharedToolText(result)
    // No channels registered → channels_exhausted, NOT verified_op_in_progress.
    #expect(!text.contains("verified_op_in_progress"))
}

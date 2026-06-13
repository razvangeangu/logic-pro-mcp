@preconcurrency import ApplicationServices
import Foundation
import Testing
@testable import LogicProMCP

// T3 — logic_plugins.insert_verified, validation gates only (R7 / AC5 / AC17 /
// AC19 / AC21). The live AX insert + fail-closed post-insert readback is T6;
// T3 fails closed at the live-write boundary after all deterministic gates pass.

private let expectedPath = "/Users/me/Music/MySong copy.logicx"

private func addEmptySlot(_ b: FakeAXRuntimeBuilder, _ id: Int) -> AXUIElement {
    let el = b.element(id)
    b.setAttribute(el, kAXRoleAttribute as String, kAXButtonRole as String)
    b.setAttribute(el, kAXDescriptionAttribute as String, "오디오 플러그인")
    b.setAttribute(el, kAXHelpAttribute as String, "오디오 이펙트 슬롯. 오디오 이펙트를 삽입합니다.")
    return el
}

private func addOccupiedSlot(_ b: FakeAXRuntimeBuilder, _ id: Int, name: String?) -> AXUIElement {
    let group = b.element(id)
    let bypass = b.element(id * 10 + 1)
    let open = b.element(id * 10 + 2)
    b.setAttribute(group, kAXRoleAttribute as String, kAXGroupRole as String)
    if let name { b.setAttribute(group, kAXDescriptionAttribute as String, name) }
    b.setChildren(group, [bypass, open])
    b.setAttribute(bypass, kAXRoleAttribute as String, kAXCheckBoxRole as String)
    b.setAttribute(bypass, kAXDescriptionAttribute as String, "바이패스")
    b.setAttribute(bypass, kAXValueAttribute as String, 0)
    b.setAttribute(open, kAXRoleAttribute as String, kAXButtonRole as String)
    b.setAttribute(open, kAXDescriptionAttribute as String, "열기")
    return group
}

private func makeMixerFixture(
    _ b: FakeAXRuntimeBuilder,
    stripChildren: (FakeAXRuntimeBuilder) -> [AXUIElement]
) -> AXLogicProElements.Runtime {
    let app = b.element(900)
    let window = b.element(901)
    let mixer = b.element(902)
    let strip = b.element(903)
    b.setAttribute(app, kAXMainWindowAttribute as String, window)
    b.setChildren(window, [mixer])
    b.setAttribute(mixer, kAXRoleAttribute as String, "AXLayoutArea")
    b.setAttribute(mixer, kAXDescriptionAttribute as String, "Mixer")
    b.setChildren(mixer, [strip])
    b.setAttribute(strip, kAXRoleAttribute as String, kAXLayoutItemRole as String)
    b.setChildren(strip, stripChildren(b))
    return b.makeLogicRuntime(appElement: app)
}

private func runInsert(
    _ params: [String: String],
    runtime: AXLogicProElements.Runtime,
    frontDoc: String? = expectedPath
) async -> [String: Any] {
    let result = await AccessibilityChannel.defaultInsertVerified(
        params: params, runtime: runtime, frontDocumentPath: { frontDoc }
    )
    return try! JSONSerialization.jsonObject(with: result.message.data(using: .utf8)!) as! [String: Any]
}

private func insertParams(
    track: String = "0", insert: String = "1",
    plugin: String = "Gain", mode: String = "duplicate_applyback",
    path: String? = expectedPath
) -> [String: String] {
    var p = ["track": track, "insert": insert, "plugin": plugin, "mode": mode]
    if let path { p["project_expected_path"] = path }
    return p
}

// MARK: - AC5: occupied slot refusal

@Test func testInsertVerifiedRefusesOccupiedSlot() async {
    let b = FakeAXRuntimeBuilder()
    let runtime = makeMixerFixture(b) { b in
        [addEmptySlot(b, 910), addOccupiedSlot(b, 911, name: "Compressor")]
    }
    // insert 1 is occupied → slot_occupied, no silent replace.
    let obj = await runInsert(insertParams(insert: "1"), runtime: runtime)
    #expect(obj["error"] as? String == "slot_occupied")
    #expect(obj["write_attempted"] as? Bool == false)
    #expect((obj["target_identity"] as? [String: Any])?["plugin_id"] as? String == "logic.stock.effect.gain")
}

// MARK: - AC21: occupied-unreadable slot is never write-safe

@Test func testInsertVerifiedRefusesOccupiedUnreadableSlot() async {
    let b = FakeAXRuntimeBuilder()
    let runtime = makeMixerFixture(b) { b in
        [addOccupiedSlot(b, 920, name: nil)] // occupied-unreadable
    }
    // An occupied-unreadable slot makes the whole snapshot incomplete, so the
    // op is refused with incomplete_inventory BEFORE the slot-occupied check —
    // either way it is never treated as empty/overwritten (AC21 / R3).
    let obj = await runInsert(insertParams(insert: "0"), runtime: runtime)
    let error = obj["error"] as? String
    #expect(error == "incomplete_inventory" || error == "slot_occupied",
            "an occupied-unreadable slot is never write-safe")
    #expect(obj["write_attempted"] as? Bool == false)
}

// MARK: - incomplete inventory refusal (R3)

@Test func testInsertVerifiedRefusesIncompleteInventory() async {
    let b = FakeAXRuntimeBuilder()
    // target slot 0 is empty, but slot 1 is unreadable → complete:false →
    // incomplete_inventory even though the target itself is readable (fail-closed).
    let runtime = makeMixerFixture(b) { b in
        [addEmptySlot(b, 930), addOccupiedSlot(b, 931, name: nil)]
    }
    let obj = await runInsert(insertParams(insert: "0"), runtime: runtime)
    #expect(obj["error"] as? String == "incomplete_inventory")
}

// MARK: - Happy-path gates pass, then fail closed at the live boundary

@Test func testInsertVerifiedAllGatesPassThenFailsClosedAtLiveBoundary() async {
    let b = FakeAXRuntimeBuilder()
    let runtime = makeMixerFixture(b) { b in
        [addEmptySlot(b, 940), addEmptySlot(b, 941)]
    }
    // Empty slot, complete inventory, valid mode/path/identity — all gates pass.
    // T3 must NOT fabricate State A; it fails closed at the live-write boundary.
    let obj = await runInsert(insertParams(insert: "0"), runtime: runtime)
    #expect(obj["state"] as? String == "C")
    #expect(obj["verified"] as? Bool == false)
    #expect(obj["write_attempted"] as? Bool == false)
    // The error must be a terminal code; the live insert path is not enabled in
    // T3, so the honest signal is not_implemented (no write attempted).
    #expect(obj["error"] as? String == "not_implemented")
    #expect(obj["success"] as? Bool == false)
}

// MARK: - mode / path / identity gates

@Test func testInsertVerifiedConfirmedLiveBlocked() async {
    let b = FakeAXRuntimeBuilder()
    let runtime = makeMixerFixture(b) { b in [addEmptySlot(b, 950)] }
    let obj = await runInsert(insertParams(mode: "confirmed_live"), runtime: runtime)
    #expect(obj["error"] as? String == "unsupported_mode")
}

@Test func testInsertVerifiedMissingPathBlocked() async {
    let b = FakeAXRuntimeBuilder()
    let runtime = makeMixerFixture(b) { b in [addEmptySlot(b, 960)] }
    let obj = await runInsert(insertParams(path: nil), runtime: runtime)
    #expect(obj["error"] as? String == "project_path_required")
}

@Test func testInsertVerifiedNoiseGateNotInsertable() async {
    // Noise Gate is identity-only, excluded from the insertable allowlist (R5).
    let b = FakeAXRuntimeBuilder()
    let runtime = makeMixerFixture(b) { b in [addEmptySlot(b, 970)] }
    let obj = await runInsert(insertParams(plugin: "Noise Gate"), runtime: runtime)
    #expect(obj["error"] as? String == "unknown_plugin_identity")
}

@Test func testInsertVerifiedUnknownIdentityBlocked() async {
    let b = FakeAXRuntimeBuilder()
    let runtime = makeMixerFixture(b) { b in [addEmptySlot(b, 980)] }
    let obj = await runInsert(insertParams(plugin: "com.apple.logic.gain"), runtime: runtime)
    #expect(obj["error"] as? String == "unknown_plugin_identity")
}

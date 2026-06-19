@preconcurrency import ApplicationServices
import Foundation
import Testing
@testable import LogicProMCP

// T3 — logic_plugins.get_inventory (drift-safe inventory, R3 / AC2 / AC12 / AC22).
// Deterministic, fixture-driven. Two layers:
//   (1) pluginInventoryItems — pure item-schema builder (AC22).
//   (2) defaultGetPluginInventory through a full mixer fixture (AC2/AC12).

// MARK: - Pure item-schema builder (AC22)

private func slot(
    _ index: Int,
    _ status: AXLogicProElements.SlotReadStatus,
    name: String? = nil,
    bypassed: Bool? = nil
) -> AXLogicProElements.PluginInsertSlot {
    // The element is irrelevant to the pure builder; reuse a throwaway app element.
    AXLogicProElements.PluginInsertSlot(
        index: index,
        element: AXUIElementCreateApplication(pid_t(9000 + index)),
        name: name,
        isBypassed: bypassed,
        readStatus: status
    )
}

@Test func testInventoryItemSchemaAlwaysCarriesAllKeys() {
    let (items, complete) = AccessibilityChannel.pluginInventoryItems(for: [
        slot(0, .occupiedReadable, name: "Gain", bypassed: false),
        slot(1, .empty),
        slot(2, .occupiedUnreadable),
    ])

    #expect(complete == false, "an unreadable slot makes the snapshot incomplete")
    #expect(items.count == 3)

    // Every item carries all six keys regardless of read_status (AC22).
    let requiredKeys: Set<String> = ["insert", "read_status", "occupied", "name", "plugin_id", "bypassed"]
    for item in items {
        #expect(Set(item.keys) == requiredKeys, "all keys must always be present, never omitted")
    }

    // read_status:"ok" — name + plugin_id (canonical match) + bypassed present.
    #expect(items[0]["read_status"] as? String == "ok")
    #expect(items[0]["occupied"] as? Bool == true)
    #expect(items[0]["name"] as? String == "Gain")
    #expect(items[0]["plugin_id"] as? String == "logic.stock.effect.gain")
    #expect(items[0]["bypassed"] as? Bool == false)

    // read_status:"empty" — name/plugin_id/bypassed are explicit null.
    #expect(items[1]["read_status"] as? String == "empty")
    #expect(items[1]["occupied"] as? Bool == false)
    #expect(items[1]["name"] is NSNull)
    #expect(items[1]["plugin_id"] is NSNull)
    #expect(items[1]["bypassed"] is NSNull)

    // read_status:"unreadable" — occupied:true, but name/plugin_id/bypassed null.
    #expect(items[2]["read_status"] as? String == "unreadable")
    #expect(items[2]["occupied"] as? Bool == true)
    #expect(items[2]["name"] is NSNull)
    #expect(items[2]["plugin_id"] is NSNull)
    #expect(items[2]["bypassed"] is NSNull)
}

@Test func testInventoryItemOccupiedReadableButNonCanonicalNameHasNullPluginID() {
    // An occupied-readable slot whose name is not an allowlisted stock plugin is
    // a real slot but NOT a verified-write target — plugin_id must be null while
    // name is preserved (§5.2 / AC22).
    let (items, complete) = AccessibilityChannel.pluginInventoryItems(for: [
        slot(0, .occupiedReadable, name: "Drum Machine Designer", bypassed: true),
    ])
    #expect(complete == true)
    #expect(items[0]["name"] as? String == "Drum Machine Designer")
    #expect(items[0]["plugin_id"] is NSNull)
    #expect(items[0]["bypassed"] as? Bool == true)
}

@Test func testInventoryAllEmptyIsComplete() {
    let (items, complete) = AccessibilityChannel.pluginInventoryItems(for: [
        slot(0, .empty), slot(1, .empty),
    ])
    #expect(complete == true)
    #expect(items.allSatisfy { ($0["read_status"] as? String) == "empty" })
}

// MARK: - Full mixer fixture (AC2 / AC12)

private func decodeObject(_ json: String) -> [String: Any] {
    try! JSONSerialization.jsonObject(with: json.data(using: .utf8)!, options: []) as! [String: Any]
}

private func addEmptySlot(_ b: FakeAXRuntimeBuilder, _ id: Int) -> AXUIElement {
    let el = b.element(id)
    b.setAttribute(el, kAXRoleAttribute as String, kAXButtonRole as String)
    b.setAttribute(el, kAXDescriptionAttribute as String, "오디오 플러그인")
    b.setAttribute(el, kAXHelpAttribute as String, "오디오 이펙트 슬롯. 오디오 이펙트를 삽입합니다.")
    return el
}

private func addEmptySlot(
    _ b: FakeAXRuntimeBuilder,
    _ id: Int,
    size: CGSize
) -> AXUIElement {
    let el = addEmptySlot(b, id)
    var mutableSize = size
    if let axSize = AXValueCreate(.cgSize, &mutableSize) {
        b.setAttribute(el, kAXSizeAttribute as String, axSize)
    }
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

/// Build a single-strip mixer fixture and return the logic runtime + app.
private func makeMixerFixture(
    _ b: FakeAXRuntimeBuilder,
    stripChildren: (FakeAXRuntimeBuilder) -> [AXUIElement]
) -> AXLogicProElements.Runtime {
    let app = b.element(700)
    let window = b.element(701)
    let mixer = b.element(702)
    let strip = b.element(703)
    b.setAttribute(app, kAXMainWindowAttribute as String, window)
    b.setChildren(window, [mixer])
    b.setAttribute(mixer, kAXRoleAttribute as String, "AXLayoutArea")
    b.setAttribute(mixer, kAXDescriptionAttribute as String, "Mixer")
    b.setChildren(mixer, [strip])
    b.setAttribute(strip, kAXRoleAttribute as String, kAXLayoutItemRole as String)
    b.setChildren(strip, stripChildren(b))
    return b.makeLogicRuntime(appElement: app)
}

@Test func testGetInventoryMixedSequencePreservesPhysicalIndex() async {
    // [occupied-readable Gain, empty, occupied-unreadable] — physical index
    // preserved, unreadable placeholder, complete:false (AC2/AC12).
    let b = FakeAXRuntimeBuilder()
    let runtime = makeMixerFixture(b) { b in
        [
            addOccupiedSlot(b, 710, name: "Gain"),
            addEmptySlot(b, 711),
            addOccupiedSlot(b, 712, name: nil),
        ]
    }

    let result = await AccessibilityChannel.defaultGetPluginInventory(params: ["track": "0"], runtime: runtime)
    #expect(result.isSuccess)
    let obj = decodeObject(result.message)

    #expect(obj["state"] as? String == "A")
    #expect(obj["success"] as? Bool == true)
    #expect(obj["verified"] as? Bool == true)
    #expect(obj["hc_schema"] as? Int == 2)
    #expect(obj["complete"] as? Bool == false)
    #expect(obj["plugins_source"] as? String == "ax")
    #expect(obj["plugins_unknown_reason"] is NSNull)
    #expect(obj["operation"] as? String == "logic_plugins.get_inventory")

    let plugins = obj["plugins"] as! [[String: Any]]
    #expect(plugins.count == 3)
    #expect(plugins.map { $0["insert"] as! Int } == [0, 1, 2])
    #expect(plugins[0]["read_status"] as? String == "ok")
    #expect(plugins[0]["plugin_id"] as? String == "logic.stock.effect.gain")
    #expect(plugins[1]["read_status"] as? String == "empty")
    #expect(plugins[2]["read_status"] as? String == "unreadable")
    #expect(plugins[2]["occupied"] as? Bool == true)
    #expect(plugins[2]["name"] is NSNull)
}

@Test func testGetInventorySkipsNonWritableShortEmptySlotStub() async {
    // Logic Pro 12.2 exposes a 9px "Audio Plug-in" button at the bottom of some
    // strips. Live E2E showed that clicking it does NOT insert into that physical
    // row; Logic appends into a different real slot. It must not be exposed as an
    // addressable insert index.
    let b = FakeAXRuntimeBuilder()
    let runtime = makeMixerFixture(b) { b in
        [
            addEmptySlot(b, 713, size: CGSize(width: 58, height: 9)),
            addOccupiedSlot(b, 714, name: "Gain"),
            addEmptySlot(b, 715, size: CGSize(width: 58, height: 18)),
        ]
    }

    let result = await AccessibilityChannel.defaultGetPluginInventory(params: ["track": "0"], runtime: runtime)
    #expect(result.isSuccess)
    let obj = decodeObject(result.message)
    let plugins = obj["plugins"] as! [[String: Any]]

    #expect(plugins.count == 2)
    #expect(plugins.map { $0["insert"] as! Int } == [0, 1])
    #expect(plugins[0]["name"] as? String == "Gain")
    #expect(plugins[1]["read_status"] as? String == "empty")
}

@Test func testGetInventoryAllReadableIsComplete() async {
    let b = FakeAXRuntimeBuilder()
    let runtime = makeMixerFixture(b) { b in
        [addOccupiedSlot(b, 720, name: "Noise Gate"), addEmptySlot(b, 721)]
    }
    let result = await AccessibilityChannel.defaultGetPluginInventory(params: ["track": "0"], runtime: runtime)
    let obj = decodeObject(result.message)
    #expect(obj["state"] as? String == "A")
    #expect(obj["success"] as? Bool == true)
    #expect(obj["verified"] as? Bool == true)
    #expect(obj["hc_schema"] as? Int == 2)
    #expect(obj["complete"] as? Bool == true)
    let plugins = obj["plugins"] as! [[String: Any]]
    #expect(plugins[0]["plugin_id"] as? String == "logic.stock.effect.noise_gate")
}

@Test func testGetInventoryStateBWhenSubtreeUnreadable() async {
    // Track index out of range → the AX subtree cannot be read → State B
    // readback_unavailable + plugins_unknown_reason (AC2). Not a fabricated
    // empty chain.
    let b = FakeAXRuntimeBuilder()
    let runtime = makeMixerFixture(b) { b in [addEmptySlot(b, 730)] }

    let result = await AccessibilityChannel.defaultGetPluginInventory(params: ["track": "5"], runtime: runtime)
    #expect(result.isSuccess) // State B is success:true, verified:false
    let obj = decodeObject(result.message)
    #expect(obj["state"] as? String == "B")
    #expect(obj["verified"] as? Bool == false)
    #expect(obj["reason"] as? String == "readback_unavailable")
    #expect(obj["plugins_unknown_reason"] as? String == "ax_subtree_unreadable")
    #expect(obj["hc_schema"] as? Int == 2)
    #expect(obj["plugins"] == nil, "State B carries no plugins array")
}

@Test func testGetInventoryRejectsMissingTrack() async {
    let b = FakeAXRuntimeBuilder()
    let runtime = makeMixerFixture(b) { b in [addEmptySlot(b, 740)] }
    let result = await AccessibilityChannel.defaultGetPluginInventory(params: [:], runtime: runtime)
    #expect(!result.isSuccess)
    let obj = decodeObject(result.message)
    #expect(obj["state"] as? String == "C")
    #expect(obj["error"] as? String == "invalid_params")
}

@Test func testGetInventoryRevealsMixerWhenInitiallyHidden() async {
    let b = FakeAXRuntimeBuilder()
    let app = b.element(760)
    let window = b.element(761)
    let runtime = b.makeLogicRuntime(appElement: app)
    b.setAttribute(app, kAXMainWindowAttribute as String, window)
    b.setChildren(window, [])

    let result = await AccessibilityChannel.defaultGetPluginInventory(
        params: ["track": "0"],
        runtime: runtime,
        revealMixer: { _ in
            let mixer = b.element(762)
            let strip = b.element(763)
            let slot = addOccupiedSlot(b, 764, name: "Gain")
            b.setAttribute(mixer, kAXRoleAttribute as String, "AXLayoutArea")
            b.setAttribute(mixer, kAXDescriptionAttribute as String, "Mixer")
            b.setAttribute(strip, kAXRoleAttribute as String, kAXLayoutItemRole as String)
            b.setChildren(strip, [slot])
            b.setChildren(mixer, [strip])
            b.setChildren(window, [mixer])
            return (
                mixer,
                .init(
                    attempted: true,
                    alreadyVisible: false,
                    strategies: ["ax_menu_view_show_mixer"],
                    menuItemFound: true,
                    menuClicked: true,
                    keySent: false,
                    mixerVisible: true
                )
            )
        }
    )

    #expect(result.isSuccess)
    let obj = decodeObject(result.message)
    #expect(obj["state"] as? String == "A")
    #expect(obj["mixer_reveal_attempted"] as? Bool == true)
    #expect((obj["mixer_reveal_strategies"] as? [String]) == ["ax_menu_view_show_mixer"])
    let plugins = obj["plugins"] as? [[String: Any]]
    #expect(plugins?.count == 1)
    #expect(plugins?.first?["plugin_id"] as? String == "logic.stock.effect.gain")
}

@Test func testGetInventoryReportsMixerNotVisibleDirectlyWhenRevealFails() async {
    let b = FakeAXRuntimeBuilder()
    let app = b.element(770)
    let window = b.element(771)
    let runtime = b.makeLogicRuntime(appElement: app)
    b.setAttribute(app, kAXMainWindowAttribute as String, window)
    b.setChildren(window, [])

    let result = await AccessibilityChannel.defaultGetPluginInventory(
        params: ["track": "0"],
        runtime: runtime,
        revealMixer: { _ in
            (
                nil,
                .init(
                    attempted: true,
                    alreadyVisible: false,
                    strategies: ["ax_menu_view_show_mixer", "cgevent_x"],
                    menuItemFound: true,
                    menuClicked: true,
                    keySent: true,
                    mixerVisible: false
                )
            )
        }
    )

    #expect(result.isSuccess)
    let obj = decodeObject(result.message)
    #expect(obj["state"] as? String == "B")
    #expect(obj["reason"] as? String == "readback_unavailable")
    #expect(obj["plugins_unknown_reason"] as? String == "mixer_not_visible")
    #expect(obj["mixer_reveal_attempted"] as? Bool == true)
    #expect(obj["mixer_reveal_menu_item_found"] as? Bool == true)
    #expect(obj["mixer_reveal_menu_clicked"] as? Bool == true)
    #expect(obj["mixer_reveal_key_sent"] as? Bool == true)
    #expect((obj["recovery_hint"] as? String)?.contains("Show Mixer") == true)
}

@preconcurrency import ApplicationServices
import Foundation
import Testing
@testable import LogicProMCP

// T2 — drift-safe insert-slot enumeration (rev-4 D1/D4, AC12/AC21).
// audioPluginInsertSlots must preserve PHYSICAL slot positions and never drop
// an occupied-but-unreadable slot, and isEmpty (= write-safe) must be true
// ONLY for a verified-empty slot.

private func addEmptySlot(_ builder: FakeAXRuntimeBuilder, _ id: Int) -> AXUIElement {
    let el = builder.element(id)
    builder.setAttribute(el, kAXRoleAttribute as String, kAXButtonRole as String)
    builder.setAttribute(el, kAXDescriptionAttribute as String, "오디오 플러그인")
    builder.setAttribute(el, kAXHelpAttribute as String, "오디오 이펙트 슬롯. 오디오 이펙트를 삽입합니다.")
    return el
}

/// Occupied slot group: AXGroup + bypass + open children. `name == nil` makes
/// it occupied-unreadable; a non-nil name makes it occupied-readable.
private func addOccupiedSlot(_ builder: FakeAXRuntimeBuilder, _ id: Int, name: String?) -> AXUIElement {
    let group = builder.element(id)
    let bypass = builder.element(id * 10 + 1)
    let open = builder.element(id * 10 + 2)
    builder.setAttribute(group, kAXRoleAttribute as String, kAXGroupRole as String)
    if let name { builder.setAttribute(group, kAXDescriptionAttribute as String, name) }
    builder.setChildren(group, [bypass, open])
    builder.setAttribute(bypass, kAXRoleAttribute as String, kAXCheckBoxRole as String)
    builder.setAttribute(bypass, kAXDescriptionAttribute as String, "바이패스")
    builder.setAttribute(bypass, kAXValueAttribute as String, 0)
    builder.setAttribute(open, kAXRoleAttribute as String, kAXButtonRole as String)
    builder.setAttribute(open, kAXDescriptionAttribute as String, "열기")
    return group
}

private func addFader(_ builder: FakeAXRuntimeBuilder, _ id: Int) -> AXUIElement {
    let el = builder.element(id)
    builder.setAttribute(el, kAXRoleAttribute as String, kAXSliderRole as String)
    builder.setAttribute(el, kAXDescriptionAttribute as String, "Volume Fader")
    return el
}

// MARK: - AC12: physical index preserved across an unreadable occupied slot

@Test func testInsertSlotsPreservePhysicalIndexAcrossUnreadableOccupied() {
    let builder = FakeAXRuntimeBuilder()
    let strip = builder.element(500)
    let occ0 = addOccupiedSlot(builder, 501, name: "Gain")
    let unread1 = addOccupiedSlot(builder, 502, name: nil)       // occupied but name unreadable
    let occ2 = addOccupiedSlot(builder, 503, name: "Compressor")
    builder.setChildren(strip, [occ0, unread1, occ2])

    let slots = AXLogicProElements.audioPluginInsertSlots(in: strip, runtime: builder.makeAXRuntime())

    #expect(slots.count == 3, "the unreadable occupied slot must NOT be dropped")
    #expect(slots[0].index == 0)
    #expect(slots[0].readStatus == .occupiedReadable)
    #expect(slots[0].name == "Gain")

    #expect(slots[1].index == 1, "physical index 1 must be preserved, not renumbered")
    #expect(slots[1].readStatus == .occupiedUnreadable)
    #expect(slots[1].name == nil)
    #expect(slots[1].occupied == true)
    #expect(slots[1].isEmpty == false, "AC21: occupied-unreadable is NOT write-safe")

    #expect(slots[2].index == 2, "the slot after an unreadable one keeps its physical index")
    #expect(slots[2].readStatus == .occupiedReadable)
    #expect(slots[2].name == "Compressor")
}

// MARK: - empty vs occupied classification

@Test func testEmptySlotIsWriteSafe() {
    let builder = FakeAXRuntimeBuilder()
    let strip = builder.element(520)
    let empty = addEmptySlot(builder, 521)
    builder.setChildren(strip, [empty])

    let slots = AXLogicProElements.audioPluginInsertSlots(in: strip, runtime: builder.makeAXRuntime())
    #expect(slots.count == 1)
    #expect(slots[0].readStatus == .empty)
    #expect(slots[0].isEmpty == true)
    #expect(slots[0].occupied == false)
    #expect(slots[0].name == nil)
}

@Test func testNonSlotChildrenDoNotConsumeAnIndex() {
    // A fader/pan between recognised slots must not shift slot indices.
    let builder = FakeAXRuntimeBuilder()
    let strip = builder.element(540)
    let fader = addFader(builder, 541)
    let empty = addEmptySlot(builder, 542)
    let occ = addOccupiedSlot(builder, 543, name: "Channel EQ")
    builder.setChildren(strip, [fader, empty, occ])

    let slots = AXLogicProElements.audioPluginInsertSlots(in: strip, runtime: builder.makeAXRuntime())
    #expect(slots.count == 2, "fader is not an insert slot")
    #expect(slots[0].readStatus == .empty && slots[0].index == 0)
    #expect(slots[1].readStatus == .occupiedReadable && slots[1].index == 1 && slots[1].name == "Channel EQ")
}

// MARK: - mixed inventory (AC12 full scenario)

@Test func testMixedReadableEmptyUnreadableSequence() {
    let builder = FakeAXRuntimeBuilder()
    let strip = builder.element(560)
    let occReadable = addOccupiedSlot(builder, 561, name: "Noise Gate")
    let empty = addEmptySlot(builder, 562)
    let occUnreadable = addOccupiedSlot(builder, 563, name: nil)
    builder.setChildren(strip, [occReadable, empty, occUnreadable])

    let slots = AXLogicProElements.audioPluginInsertSlots(in: strip, runtime: builder.makeAXRuntime())
    #expect(slots.map(\.readStatus) == [.occupiedReadable, .empty, .occupiedUnreadable])
    #expect(slots.map(\.index) == [0, 1, 2])
    #expect(slots[2].isEmpty == false, "an unreadable slot is never treated as the empty slot")
}

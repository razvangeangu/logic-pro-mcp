import ApplicationServices
import Foundation
import Testing
@testable import LogicProMCP

/// #106 regression: Logic 12.x track-header Mute/Solo/Record-enable controls
/// are `AXCheckBox` elements, not `AXButton`. The pre-fix Mute/Solo locators
/// searched only `kAXButtonRole`, returned nil, and the whole channel chain
/// fell through to `channels_exhausted`. `findTrackToggleControl` must match
/// the checkbox by its (localized) description.
@Suite("Issue106 track-toggle locator")
struct Issue106TrackToggleLocatorTests {
    private struct Header {
        let builder: FakeAXRuntimeBuilder
        let header: AXUIElement
        let runtime: AXLogicProElements.Runtime
        let mute: AXUIElement
        let solo: AXUIElement
        let arm: AXUIElement
    }

    /// Build a fake track header whose children are the four Logic 12.x
    /// checkboxes (Mute / Solo / Record Enable / Input Monitoring), localized
    /// per `descriptions`.
    private func makeHeader(_ descriptions: (mute: String, solo: String, arm: String)) -> Header {
        let b = FakeAXRuntimeBuilder()
        let header = b.element(1)
        b.setAttribute(header, kAXRoleAttribute, "AXLayoutItem")
        func checkbox(_ id: Int, _ desc: String) -> AXUIElement {
            let e = b.element(id)
            b.setAttribute(e, kAXRoleAttribute, "AXCheckBox")
            b.setAttribute(e, kAXDescriptionAttribute, desc)
            b.setAttribute(e, kAXValueAttribute, 0)
            return e
        }
        let mute = checkbox(2, descriptions.mute)
        let solo = checkbox(3, descriptions.solo)
        let arm = checkbox(4, descriptions.arm)
        let input = checkbox(5, "Input Monitoring")
        b.setChildren(header, [mute, solo, arm, input])
        return Header(builder: b, header: header, runtime: b.makeLogicRuntime(), mute: mute, solo: solo, arm: arm)
    }

    private func sameElement(_ a: AXUIElement?, _ b: AXUIElement) -> Bool {
        guard let a else { return false }
        return CFEqual(a, b)
    }

    @Test("English checkboxes: Mute/Solo/Record Enable are located")
    func englishCheckboxes() {
        let h = makeHeader((mute: "Mute", solo: "Solo", arm: "Record Enable"))
        let mute = AXLogicProElements.findTrackToggleControl(
            in: h.header, labels: AXLocalePolicy.trackMuteButton.labels, legacyTitle: "M", runtime: h.runtime)
        let solo = AXLogicProElements.findTrackToggleControl(
            in: h.header, labels: AXLocalePolicy.trackSoloButton.labels, legacyTitle: "S", runtime: h.runtime)
        let arm = AXLogicProElements.findTrackToggleControl(
            in: h.header, labels: AXLocalePolicy.trackRecordEnableCheckbox.labels, legacyTitle: "R", runtime: h.runtime)
        #expect(sameElement(mute, h.mute))
        #expect(sameElement(solo, h.solo))
        #expect(sameElement(arm, h.arm))
    }

    @Test("Korean checkboxes: 음소거/솔로/녹음 활성화 are located")
    func koreanCheckboxes() {
        let h = makeHeader((mute: "음소거", solo: "솔로", arm: "녹음 활성화"))
        let mute = AXLogicProElements.findTrackToggleControl(
            in: h.header, labels: AXLocalePolicy.trackMuteButton.labels, legacyTitle: "M", runtime: h.runtime)
        let solo = AXLogicProElements.findTrackToggleControl(
            in: h.header, labels: AXLocalePolicy.trackSoloButton.labels, legacyTitle: "S", runtime: h.runtime)
        let arm = AXLogicProElements.findTrackToggleControl(
            in: h.header, labels: AXLocalePolicy.trackRecordEnableCheckbox.labels, legacyTitle: "R", runtime: h.runtime)
        #expect(sameElement(mute, h.mute))
        #expect(sameElement(solo, h.solo))
        #expect(sameElement(arm, h.arm))
    }

    @Test("does not mismatch the Input Monitoring checkbox")
    func inputMonitoringNotMistaken() {
        let h = makeHeader((mute: "Mute", solo: "Solo", arm: "Record Enable"))
        // The arm matcher's "Record" prefix must not bind to Input Monitoring.
        let arm = AXLogicProElements.findTrackToggleControl(
            in: h.header, labels: AXLocalePolicy.trackRecordEnableCheckbox.labels, legacyTitle: "R", runtime: h.runtime)
        #expect(sameElement(arm, h.arm))
        #expect(!sameElement(arm, h.builder.element(5)))
    }

    @Test("returns nil when no matching control exists (fail-closed)")
    func noMatchReturnsNil() {
        let b = FakeAXRuntimeBuilder()
        let header = b.element(1)
        b.setAttribute(header, kAXRoleAttribute, "AXLayoutItem")
        let unrelated = b.element(2)
        b.setAttribute(unrelated, kAXRoleAttribute, "AXCheckBox")
        b.setAttribute(unrelated, kAXDescriptionAttribute, "Input Monitoring")
        b.setChildren(header, [unrelated])
        let mute = AXLogicProElements.findTrackToggleControl(
            in: header, labels: AXLocalePolicy.trackMuteButton.labels, legacyTitle: "M", runtime: b.makeLogicRuntime())
        #expect(mute == nil)
    }

    @Test("legacy AXButton fallback still works for older builds")
    func legacyButtonFallback() {
        // No checkboxes; a legacy AXButton with a "Mute" description.
        let b = FakeAXRuntimeBuilder()
        let header = b.element(1)
        b.setAttribute(header, kAXRoleAttribute, "AXLayoutItem")
        let muteButton = b.element(2)
        b.setAttribute(muteButton, kAXRoleAttribute, "AXButton")
        b.setAttribute(muteButton, kAXDescriptionAttribute, "Mute")
        b.setChildren(header, [muteButton])
        let mute = AXLogicProElements.findTrackToggleControl(
            in: header, labels: AXLocalePolicy.trackMuteButton.labels, legacyTitle: "M", runtime: b.makeLogicRuntime())
        #expect(sameElement(mute, muteButton))
    }
}

import ApplicationServices
import Foundation
import Testing
@testable import LogicProMCP

/// #107 deterministic coverage for the mixer-write value mapping + the
/// track-header fader/pan locators. The AXIncrement/AXDecrement nudge loop
/// itself runs against live Logic (covered by the live E2E probe); these tests
/// pin the pure math + locator selection that the nudge relies on.
@Suite("Issue107 mixer write")
struct Issue107MixerWriteTests {
    @Test("volume contract↔raw round-trips through the fader taper")
    func volumeContractRawRoundTrip() {
        let range = AXValueExtractors.SliderRange(min: 0, max: 233)
        for contract in [0.0, 0.2, 0.4, 0.5, 0.6, 0.8, 1.0] {
            let raw = AXValueExtractors.logicMixerFaderContractToRaw(contract, range: range)
            #expect(raw >= 0 && raw <= 233)
            let position = (raw - range.min) / (range.max - range.min)
            let back = AXValueExtractors.logicMixerFaderPositionToContract(position)
            #expect(abs(back - contract) < 0.0001,
                    "contract \(contract) -> raw \(raw) -> contract \(back)")
        }
    }

    @Test("volume contract→raw is monotonic increasing")
    func volumeMonotonic() {
        let range = AXValueExtractors.SliderRange(min: 0, max: 233)
        var last = -1.0
        for contract in stride(from: 0.0, through: 1.0, by: 0.05) {
            let raw = AXValueExtractors.logicMixerFaderContractToRaw(contract, range: range)
            #expect(raw >= last - 0.0001, "raw must not decrease as contract rises (\(contract) -> \(raw))")
            last = raw
        }
    }

    @Test("header pan: raw center→0, rails→±1")
    func headerPanMapping() {
        let b = FakeAXRuntimeBuilder()
        let range = AXValueExtractors.SliderRange(min: 0, max: 127)
        func panContract(_ raw: Int) -> Double? {
            let e = b.element(raw + 1)
            b.setAttribute(e, kAXValueAttribute, raw)
            return AXValueExtractors.headerPanContract(e, range: range, runtime: b.makeAXRuntime())
        }
        #expect(abs((panContract(64) ?? -9) - 0.0079) < 0.01) // midpoint ≈ center
        #expect(abs((panContract(0) ?? 9) - (-1.0)) < 0.0001)
        #expect(abs((panContract(127) ?? -9) - 1.0) < 0.0001)
        #expect((panContract(96) ?? 0) > 0)  // right of center
        #expect((panContract(32) ?? 0) < 0)  // left of center
    }

    /// Build a fake track header: a "Volume"-described AXSlider plus a
    /// description-less pan AXSlider whose AXValueIndicator child reads "0 Pan".
    private func makeHeader() -> (b: FakeAXRuntimeBuilder, header: AXUIElement, vol: AXUIElement, pan: AXUIElement) {
        let b = FakeAXRuntimeBuilder()
        let header = b.element(1)
        b.setAttribute(header, kAXRoleAttribute, "AXLayoutItem")
        let pan = b.element(2)
        b.setAttribute(pan, kAXRoleAttribute, "AXSlider")
        b.setAttribute(pan, kAXDescriptionAttribute, "")
        let panIndicator = b.element(3)
        b.setAttribute(panIndicator, kAXRoleAttribute, "AXValueIndicator")
        b.setAttribute(panIndicator, kAXDescriptionAttribute, "0 Pan")
        b.setChildren(pan, [panIndicator])
        let vol = b.element(4)
        b.setAttribute(vol, kAXRoleAttribute, "AXSlider")
        b.setAttribute(vol, kAXDescriptionAttribute, "Volume")
        b.setChildren(header, [pan, vol])
        return (b, header, vol, pan)
    }

    @Test("findVolumeFader picks the Volume-described slider in a header")
    func volumeFaderLocator() {
        let h = makeHeader()
        let found = AXLogicProElements.findVolumeFader(in: h.header, runtime: h.b.makeAXRuntime())
        #expect(found != nil && CFEqual(found!, h.vol))
    }

    @Test("findPanControlInHeader picks the pan slider, not the volume fader")
    func panLocator() {
        let h = makeHeader()
        let found = AXLogicProElements.findPanControlInHeader(h.header, runtime: h.b.makeAXRuntime())
        #expect(found != nil && CFEqual(found!, h.pan))
        let vol = AXLogicProElements.findVolumeFader(in: h.header, runtime: h.b.makeAXRuntime())
        #expect(found != nil && vol != nil && !CFEqual(found!, vol!))
    }
}

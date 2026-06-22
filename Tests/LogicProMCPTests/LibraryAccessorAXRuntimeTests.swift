@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation
import Testing
@testable import LogicProMCP

private func libraryAXPoint(_ x: CGFloat, _ y: CGFloat) -> AXValue {
    var point = CGPoint(x: x, y: y)
    return AXValueCreate(.cgPoint, &point)!
}

private func libraryAXSize(_ width: CGFloat, _ height: CGFloat) -> AXValue {
    var size = CGSize(width: width, height: height)
    return AXValueCreate(.cgSize, &size)!
}

private func makeLibraryPanelFixture() -> (
    builder: FakeAXRuntimeBuilder,
    runtime: AXLogicProElements.Runtime,
    library: LibraryAccessor.Runtime,
    categoryList: AXUIElement,
    presetList: AXUIElement
) {
    let builder = FakeAXRuntimeBuilder()
    let app = builder.element(10_000)
    let window = builder.element(10_001)
    let browser = builder.element(10_002)
    let categoryList = builder.element(10_003)
    let presetList = builder.element(10_004)
    let bass = builder.element(10_005)
    let drums = builder.element(10_006)
    let sub = builder.element(10_007)
    let funky = builder.element(10_008)

    builder.setAttribute(app, kAXMainWindowAttribute as String, window)
    builder.setChildren(window, [browser])
    builder.setAttribute(browser, kAXRoleAttribute as String, kAXBrowserRole as String)
    builder.setAttribute(browser, kAXDescriptionAttribute as String, "Library")
    builder.setChildren(browser, [categoryList, presetList])

    builder.setAttribute(categoryList, kAXRoleAttribute as String, kAXListRole as String)
    builder.setChildren(categoryList, [bass, drums])
    builder.setAttribute(presetList, kAXRoleAttribute as String, kAXListRole as String)
    builder.setChildren(presetList, [sub, funky])

    for (element, value, x, y, parent) in [
        (bass, "Bass", CGFloat(100), CGFloat(100), categoryList),
        (drums, "Drums", CGFloat(100), CGFloat(130), categoryList),
        (sub, "Sub", CGFloat(260), CGFloat(100), presetList),
        (funky, "Funky", CGFloat(260), CGFloat(130), presetList),
    ] {
        builder.setAttribute(element, kAXRoleAttribute as String, kAXStaticTextRole as String)
        builder.setAttribute(element, kAXValueAttribute as String, value)
        builder.setAttribute(element, kAXPositionAttribute as String, libraryAXPoint(x, y))
        builder.setAttribute(element, kAXSizeAttribute as String, libraryAXSize(80, 20))
        builder.setAttribute(element, kAXParentAttribute as String, parent)
    }

    builder.setAttribute(categoryList, kAXSelectedChildrenAttribute as String, [bass])
    builder.setAttribute(presetList, kAXSelectedChildrenAttribute as String, [sub])

    let runtime = builder.makeLogicRuntime(appElement: app)
    let library = LibraryAccessor.Runtime(
        ax: runtime.ax,
        postMouseClick: { _ in true }
    )
    return (builder, runtime, library, categoryList, presetList)
}

@Test func libraryAccessorEnumerateUsesInjectedAXRuntimeForColumnsAndSelection() {
    let fixture = makeLibraryPanelFixture()

    let inventory = LibraryAccessor.enumerate(runtime: fixture.runtime)

    #expect(inventory?.categories == ["Bass", "Drums"])
    #expect(inventory?.presetsByCategory["Bass"] == ["Sub", "Funky"])
    #expect(inventory?.currentCategory == "Bass")
    #expect(inventory?.currentPreset == "Sub")
    #expect(LibraryAccessor.currentPresets(runtime: fixture.runtime) == ["Sub", "Funky"])
    #expect(LibraryAccessor.isLibraryPanelOpen(runtime: fixture.runtime) == true)
}

@Test func libraryAccessorSegmentVisibleDetectsRowInVisibleBrowser() {
    // #135 — selectPath's segment-timing hardening polls for the next
    // segment's AXStaticText. `segmentIsVisible` is the read-only primitive
    // that poll uses: present rows → true, absent rows → false.
    let fixture = makeLibraryPanelFixture()

    #expect(LibraryAccessor.segmentIsVisible(named: "Sub", runtime: fixture.runtime))
    #expect(LibraryAccessor.segmentIsVisible(named: "Bass", runtime: fixture.runtime))
    #expect(!LibraryAccessor.segmentIsVisible(named: "Acid Etched Bass", runtime: fixture.runtime))
}

@Test func libraryAccessorWaitForSegmentReturnsPromptlyWhenAlreadyVisible() {
    // Already-visible row must not burn the full timeout.
    let fixture = makeLibraryPanelFixture()
    let start = Date()
    LibraryAccessor.waitForSegmentVisible(
        named: "Sub", timeout: 1.0, pollInterval: 0.02, runtime: fixture.runtime
    )
    #expect(Date().timeIntervalSince(start) < 0.5)
}

@Test func libraryAccessorSelectionUsesInjectedSetAttributeAndActionRuntime() {
    let fixture = makeLibraryPanelFixture()

    #expect(LibraryAccessor.selectCategory(
        named: "Bass",
        runtime: fixture.runtime,
        library: fixture.library
    ) == true)
    #expect(LibraryAccessor.selectPreset(
        named: "Sub",
        runtime: fixture.runtime,
        library: fixture.library
    ) == true)
    #expect(LibraryAccessor.setInstrument(
        category: "Bass",
        preset: "Sub",
        settleDelay: 0,
        runtime: fixture.runtime,
        library: fixture.library
    ) == true)

    #expect(fixture.builder.setCalls.contains { $0.attribute == kAXSelectedChildrenAttribute as String })
    #expect(fixture.builder.actionCalls.contains { $0.action == kAXPressAction as String })
}

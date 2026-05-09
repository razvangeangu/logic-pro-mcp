import ApplicationServices
import CoreGraphics
import Testing
@testable import LogicProMCP

// H-6 (2026-05-08 enterprise review): `AXHelpers.getPosition` and
// `getSize` used to force-cast the raw attribute value to `AXValue`
// without a `CFGetTypeID` guard. Malformed AX attributes (Logic build
// drift, plugin mock, AX timeout returning a stub) could crash the
// server process instead of degrading to a `nil` return.
//
// These tests pin the new guarded behaviour: when the attribute value's
// `CFTypeID` does not match `AXValueGetTypeID()`, both helpers must
// return `nil`. The existing AX-aware helpers (`LibraryAccessor`,
// `PluginInspector`, `AXLogicProElements`) already use this pattern;
// the fix brings `AXHelpers` into alignment.

// `Runtime.attributeValue` is `@Sendable`; closure captures must be Sendable
// too. We pass the desired return value as a CFTypeRef-castable Sendable wrapper.
private final class AttributeBox: @unchecked Sendable {
    let value: AnyObject?
    init(_ value: AnyObject?) { self.value = value }
}

private func makeRuntime(returning: AnyObject?) -> AXHelpers.Runtime {
    let box = AttributeBox(returning)
    return AXHelpers.Runtime(
        axApp: { _ in AXUIElementCreateSystemWide() },
        attributeValue: { _, _ in box.value },
        setAttributeValue: { _, _, _ in true },
        children: { _ in [] },
        performAction: { _, _ in true },
        childCount: { _ in 0 }
    )
}

@Test func testGetPositionReturnsNilOnNonAXValueAttribute() {
    // CFString masquerading as a position attr — pre-fix this crashed
    // with `Could not cast value of type '__NSCFString' to 'AXValue'`.
    let runtime = makeRuntime(returning: "10,20" as NSString)
    let result = AXHelpers.getPosition(AXUIElementCreateSystemWide(), runtime: runtime)
    #expect(result == nil)
}

@Test func testGetSizeReturnsNilOnNonAXValueAttribute() {
    // CFNumber masquerading as a size attr.
    let runtime = makeRuntime(returning: NSNumber(value: 42))
    let result = AXHelpers.getSize(AXUIElementCreateSystemWide(), runtime: runtime)
    #expect(result == nil)
}

@Test func testGetPositionReturnsNilWhenAttributeAbsent() {
    let runtime = makeRuntime(returning: nil)
    let result = AXHelpers.getPosition(AXUIElementCreateSystemWide(), runtime: runtime)
    #expect(result == nil)
}

@Test func testGetSizeReturnsNilWhenAttributeAbsent() {
    let runtime = makeRuntime(returning: nil)
    let result = AXHelpers.getSize(AXUIElementCreateSystemWide(), runtime: runtime)
    #expect(result == nil)
}

@Test func testGetPositionReturnsValueOnWellFormedAXValue() {
    // Construct a real AXValue from a CGPoint. AXValue carries a CFTypeID
    // that matches `AXValueGetTypeID()`, so the guard lets it through.
    var point = CGPoint(x: 100, y: 200)
    let axValue = AXValueCreate(.cgPoint, &point)!
    let runtime = makeRuntime(returning: axValue)
    let result = AXHelpers.getPosition(AXUIElementCreateSystemWide(), runtime: runtime)
    #expect(result == CGPoint(x: 100, y: 200))
}

@Test func testGetSizeReturnsValueOnWellFormedAXValue() {
    var size = CGSize(width: 300, height: 150)
    let axValue = AXValueCreate(.cgSize, &size)!
    let runtime = makeRuntime(returning: axValue)
    let result = AXHelpers.getSize(AXUIElementCreateSystemWide(), runtime: runtime)
    #expect(result == CGSize(width: 300, height: 150))
}

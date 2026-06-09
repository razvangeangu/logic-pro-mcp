import ApplicationServices
import CoreGraphics
import Foundation
import Testing
@testable import LogicProMCP

/// H2 (P2-5) — coord-click fallbacks must fail closed on a malformed AX value.
/// Before the fix, four call sites checked `CFGetTypeID == AXValueGetTypeID()`
/// but ignored `AXValueGetValue`'s Bool result, so a wrong-subtype AXValue
/// (e.g. a `.cgRect` where a `.cgPoint` was expected) silently produced a
/// (0,0) point and the code clicked the top-left corner / computed a bogus
/// viewport. The shared `AXHelpers.point/size(fromRawAttribute:)` helpers now
/// return nil in that case and every call site abandons the click.
@Suite struct AXCoordFallbackTests {

    @Test func testPointFromValidCGPointAXValue() {
        var pt = CGPoint(x: 12, y: 34)
        let v = AXValueCreate(.cgPoint, &pt)!
        #expect(AXHelpers.point(fromRawAttribute: v) == CGPoint(x: 12, y: 34))
    }

    @Test func testSizeFromValidCGSizeAXValue() {
        var sz = CGSize(width: 100, height: 50)
        let v = AXValueCreate(.cgSize, &sz)!
        #expect(AXHelpers.size(fromRawAttribute: v) == CGSize(width: 100, height: 50))
    }

    // The regression: a real AXValue, CFGetTypeID matches, but the requested
    // subtype extraction fails → must be nil (fail-closed), not (0,0).
    @Test func testPointRejectsWrongSubtypeAXValue() {
        var rect = CGRect(x: 1, y: 2, width: 3, height: 4)
        let v = AXValueCreate(.cgRect, &rect)!
        #expect(AXHelpers.point(fromRawAttribute: v) == nil)
    }

    @Test func testSizeRejectsWrongSubtypeAXValue() {
        var rect = CGRect(x: 1, y: 2, width: 3, height: 4)
        let v = AXValueCreate(.cgRect, &rect)!
        #expect(AXHelpers.size(fromRawAttribute: v) == nil)
    }

    @Test func testRejectsNonAXValue() {
        let s = "not an axvalue" as CFString
        #expect(AXHelpers.point(fromRawAttribute: s) == nil)
        #expect(AXHelpers.size(fromRawAttribute: s) == nil)
    }

    @Test func testRejectsNil() {
        #expect(AXHelpers.point(fromRawAttribute: nil) == nil)
        #expect(AXHelpers.size(fromRawAttribute: nil) == nil)
    }
}

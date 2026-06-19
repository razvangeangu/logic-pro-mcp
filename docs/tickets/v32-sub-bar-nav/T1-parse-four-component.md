# T1 — `parseFourComponentPosition` Helper

> Historical record. Current release-candidate evidence is in `README.md`, `CHANGELOG.md`, and `docs/live-verify-v3.6.0.md`; published stable evidence remains in `docs/live-verify-v3.5.0.md`; this file remains preserved implementation context.

**Status**: Todo (proceed after T0 PASS)
**Size**: S
**Depends on**: T0
**PRD**: AC-1.1, AC-2.1~2.4, AC-4.4, AC-4.5

## Goal

Extract a helper function that accurately parses the 4-component string from `params["position"]` in `gotoPositionViaBarSlider`. This has a different responsibility from the v3.1.11 parser (`parseMarkerListPosition`) — this is caller validation/extraction.

## Background

v3.1.11 code:

```swift
// AccessibilityChannel.swift:2206-2208
let parts = pos.split(separator: ".")
if let first = parts.first, let b = Int(first) {
    targetBar = b
}
```

Extracts only the first component. v3.2 — extract all 4 components.

TransportDispatcher already validates 4-component format via `isValidPositionString` → by the time `pos` reaches AccessibilityChannel, it is a valid 4-component string. However, the AX channel also maintains self-contained validation (defense in depth).

## TDD Red Phase

Add to `Tests/LogicProMCPTests/AXGotoPositionTests.swift` (or new file):

```swift
@Test("parseFourComponentPosition: valid → (bar, beat, div, tick)", arguments: [
    ("146.4.4.240", (146, 4, 4, 240)),
    ("1.1.1.1", (1, 1, 1, 1)),
    ("9999.16.16.999", (9999, 16, 16, 999)),
])
func parseFourComponentPosition_valid(input: String, expected: (Int, Int, Int, Int)) {
    let parsed = AccessibilityChannel.parseFourComponentPosition(input)
    #expect(parsed?.bar == expected.0)
    #expect(parsed?.beat == expected.1)
    #expect(parsed?.div == expected.2)
    #expect(parsed?.tick == expected.3)
}

@Test("parseFourComponentPosition: invalid → nil", arguments: [
    "", "146", "146.4", "146.4.4", "146.4.4.240.1",
    "0.1.1.1", "10000.1.1.1", "146.17.4.240", "146.4.17.240", "146.4.4.1000",
    "abc.4.4.240", "146.+4.4.240", "146.-4.4.240", "146.4.4.240.",
    "00:01:30:00",
])
func parseFourComponentPosition_invalid(input: String) {
    #expect(AccessibilityChannel.parseFourComponentPosition(input) == nil)
}
```

**Red confirmation**: Before the function is defined — `parseFourComponentPosition` does not exist → compile error → Red.

## Green Phase Implementation

Add to `Sources/LogicProMCP/Channels/AccessibilityChannel.swift`:

```swift
/// Parses the 4-component position string for `transport.goto_position`.
///
/// Input arrives after TransportDispatcher.isValidPositionString validation,
/// but the AX channel also maintains self-contained validation — defense-in-depth.
/// Bounds: bar 1..9999, beat 1..16, div 1..16, tick 1..999.
/// Rejects `+`/`-` prefix, non-ASCII digits, and timecode (contains `:`).
struct FourComponentPosition: Equatable {
    let bar: Int
    let beat: Int
    let div: Int
    let tick: Int
}

static func parseFourComponentPosition(_ raw: String) -> FourComponentPosition? {
    // Explicitly reject timecode (defense against wrong channel routing by caller).
    guard !raw.contains(":") else { return nil }
    let parts = raw.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    guard parts.count == 4 else { return nil }
    // ASCII 0-9 char-set check (same policy as v3.1.11 NG9).
    let asciiDigit = { (s: String) -> Bool in
        !s.isEmpty && s.allSatisfy { $0.isASCII && $0.isNumber }
    }
    guard parts.allSatisfy(asciiDigit),
          let bar = Int(parts[0]), (1...9999).contains(bar),
          let beat = Int(parts[1]), (1...16).contains(beat),
          let div = Int(parts[2]), (1...16).contains(div),
          let tick = Int(parts[3]), (1...999).contains(tick) else {
        return nil
    }
    return FourComponentPosition(bar: bar, beat: beat, div: div, tick: tick)
}
```

Body ≤ 25 lines (AC-4.5).

## Refactor Phase

- Verify comments (no English comments — AC-4.1)
- grep TODO/FIXME 0 (AC-4.2)
- `static`/`internal` visibility — tests need internal access. Swift Testing uses `@testable import` → `static func` is sufficient
- Naming: Swift API Design Guidelines (`parseFourComponentPosition` — verb phrase, side-effect-free query). Struct `FourComponentPosition` PascalCase

## Acceptance Criteria

- **AC-T1.1**: `AccessibilityChannel.parseFourComponentPosition` added, body ≤ 25 lines
- **AC-T1.2**: parameterized test 3 valid + 15 invalid cases PASS
- **AC-T1.3**: No English comments (git diff grep verified)
- **AC-T1.4**: No new TODO/FIXME/XXX
- **AC-T1.5**: Existing 1064 tests: 0 regressions (PASS maintained)
- **AC-T1.6**: SOLID/SRP — responsibility separated from parser function (`parseMarkerListPosition`): parser handles AX surface conversion; this function handles caller input extraction

## Out of Scope

- This helper is extraction only — actual navigation is T2
- TransportDispatcher validation unchanged (existing isValidPositionString kept)
- 1-component or SMPTE handling is branched at the call site (T2)

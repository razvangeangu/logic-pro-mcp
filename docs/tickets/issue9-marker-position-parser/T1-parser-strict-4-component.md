# T1: parseMarkerListPosition strict 4-component fix

**PRD Ref**: PRD-issue9 > US-1, US-2 (parser scope)
**Priority**: P0
**Size**: S (< 1h)
**Status**: Todo
**Depends On**: None

---

## 1. Objective
Implement `AXLogicProElements.parseMarkerListPosition` exactly as described in PRD §4.4 sketch. 18-20 lines (doc + body), single responsibility.

## 2. Acceptance Criteria
- [ ] AC-1: Function body ≤ 13 lines (from signature `{` to `}`).
- [ ] AC-2: API signature unchanged: `static func parseMarkerListPosition(_ raw: String) -> String?`.
- [ ] AC-3: Foundation API only — regex / NSRegularExpression / external libraries: 0.
- [ ] AC-4: NG7 (mixed separator) / NG8 (1-based) / NG9 (ASCII narrow) / NG11 (strict 4) all satisfied.
- [ ] AC-5: Foundation API only — regex / NSRegularExpression / external libraries: 0.
- [ ] AC-6: SOLID/SRP — pure function, side-effect 0, no calls to other modules.
- [ ] AC-7: `swift build -c release` 0 warnings.

## 3. TDD Spec (Red Phase)

T1 alone is implementation. Red tests are added in T2 — T2 Red → T1 Green → T2 parameterized validation.

Order of execution:
1. T2 first: write 25 new test cases → confirm all fail (Red).
2. T1 implementation → confirm all T2 cases pass (Green).
3. Commit T1 + T2 together.

## 4. Implementation

### 4.1 Files to Modify
| File | Change |
|------|--------|
| `Sources/LogicProMCP/Accessibility/AXLogicProElements.swift` | Replace `parseMarkerListPosition` body + doc |

### 4.2 Implementation (PRD §4.4)

Replace the existing function (line 868-880, 14 lines) with the following:

```swift
/// Converts a position string from a Logic Marker List cell into the canonical "bar.beat.div.tick" form.
///
/// Observed input variants:
/// - Korean 12.2: "1 1 1 1" (space-separated, whole-bar)
/// - English 12.2: "146 4 4 240." (space-separated + trailing dot from UI rendering)
///
/// Requires exactly 4 components, each an ASCII integer ≥ 1. Logic UI always exposes 4
/// components, so 1-3 components are likely non-position cells (e.g., tempo) and
/// return nil. The caller uses the `\(index+1).1.1.1` fallback.
static func parseMarkerListPosition(_ raw: String) -> String? {
    // Trailing dot/comma are Logic UI rendering artifacts — strip in a loop.
    var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    while let last = trimmed.last, last == "." || last == "," {
        trimmed.removeLast()
    }
    // Space/tab only as separator (Logic uses spaces only; dots are meaningful only at the end).
    let parts = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
    // Exactly 4 components + ASCII integer + 1-based.
    guard parts.count == 4,
          parts.allSatisfy({ Int($0).map { $0 >= 1 } == true }) else {
        return nil
    }
    return parts.joined(separator: ".")
}
```

### 4.3 Refactor (post-Green)
- `Int($0).map { $0 >= 1 } == true` readability comparison: `(Int($0) ?? 0) >= 1` is most compact (15 chars vs 27 chars). If input is `0`, `0 >= 1` is false — same semantics. **Selection**: `(Int($0) ?? 0) >= 1` (readability + compact).

Final v0.4 sketch:
```swift
guard parts.count == 4,
      parts.allSatisfy({ (Int($0) ?? 0) >= 1 }) else {
    return nil
}
```

### 4.4 Verification
- `swift build -c release` 0 warnings
- `wc -l` body ≤ 13 lines

## 5. Edge Cases
All covered by the 25-case matrix in T2.

## 6. Review Checklist (11-principle mapping)
- [x] Apple-level — Foundation API only, 13 lines body
- [x] Dead code 0
- [x] SOLID — single responsibility (string → canonical)
- [x] Readability — intent clear at each step
- [x] Compact — 5 line body
- [x] Standard — Swift API Design Guidelines compliant

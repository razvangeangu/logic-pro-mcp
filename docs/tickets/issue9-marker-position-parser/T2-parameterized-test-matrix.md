# T2: parameterized test matrix (Swift Testing 25 cases)

> Historical record. Current stable evidence is in `README.md`, `CHANGELOG.md`, and `docs/live-verify-v3.7.0.md`; previous stable evidence remains in `docs/live-verify-v3.6.0.md`; this file remains preserved implementation context.

**PRD Ref**: PRD-issue9 > §8.1
**Priority**: P0
**Size**: S (< 1h)
**Status**: Todo
**Depends On**: T1 (Green validation after implementation)

---

## 1. Objective
Write the 14 edge cases from PRD §5 + 1 integration regression compactly as Swift Testing parameterized tests. Move the existing v3.1.10 valid case `"17 2"` (lenient 2-component) explicitly to invalid.

## 2. Acceptance Criteria
- [ ] AC-1: 8 new valid cases + 17 invalid cases — only 2 `@Test(arguments:)` functions.
- [ ] AC-2: Delete existing v3.1.10 tests `parseMarkerListPosition_validInputs` / `_invalidInputs` — merged into parameterized.
- [ ] AC-3: All 25 cases PASS after T1 implementation.
- [ ] AC-4: Line count ≤ 50 (parameterized compression).

## 3. TDD Spec (Red Phase)

### 3.1 Test 1: Valid inputs (8 cases)
```swift
@Test("parseMarkerListPosition: valid input → canonical form", arguments: [
    ("1 1 1 1", "1.1.1.1"),                     // Korean 12.2 whole-bar
    ("146 4 4 240", "146.4.4.240"),             // English 12.2 non-bar-aligned
    ("146 4 4 240.", "146.4.4.240"),            // ★ English UI trailing dot (core fix)
    ("146 4 4 240,", "146.4.4.240"),            // trailing comma guard
    ("  146 4 4 240  ", "146.4.4.240"),         // leading/trailing whitespace
    ("146  4  4  240", "146.4.4.240"),          // multiple spaces
    ("146\t4\t4\t240", "146.4.4.240"),          // tab separators
    ("17 2 3 4", "17.2.3.4"),                   // exactly 4 components
])
func parseMarkerListPosition_valid(input: String, expected: String) {
    #expect(AXLogicProElements.parseMarkerListPosition(input) == expected)
}
```

### 3.2 Test 2: Invalid inputs (17 cases)
```swift
@Test("parseMarkerListPosition: invalid input → nil", arguments: [
    "", "   ", ".",                              // empty / meaningless
    "abc", "1 abc", "1 2 3 x",                   // non-numeric mix
    "1", "17 2", "1 2 3",                        // ★ NG11 strict — 1-3 components rejected
    "1 2 3 4 5", "1 2 3 4 5 6",                  // 5+ components
    "0 0 0 0", "0 1 1 1", "1 0 1 1",             // NG8 1-based violation
    "١٤٦ ٤ ٤ ٢٤٠",                              // NG9 ASCII narrow (Arabic-Indic)
    "1.1 1.1", "146.4 4 240",                    // NG7 mixed separator
])
func parseMarkerListPosition_invalid(input: String) {
    #expect(AXLogicProElements.parseMarkerListPosition(input) == nil)
}
```

### 3.3 Integration regression (split to T3 — caller fallback)
Written separately in T3.

## 4. Implementation Steps

1. **Red**: Add the 2 `@Test` functions above to `Tests/LogicProMCPTests/AXMarkers12MarkerListTests.swift`. Preserve existing v3.1.10 valid/invalid tests for now.
2. **Run**: `swift test --filter parseMarkerListPosition_valid` → confirm trailing-dot and other new cases FAIL (Red).
3. **Green** (after T1 implementation): all 25 cases PASS.
4. **Refactor**: Delete v3.1.10 `_validInputs` / `_invalidInputs`. Merge into the 2 parameterized tests.
5. **Final run**: `swift test --no-parallel` 1062 → 1075+ PASS.

## 5. Edge Cases
All cases from PRD §5 covered.

## 6. Review Checklist
- [x] swift-testing-pro pattern (parameterized)
- [x] Compact (50 lines)
- [x] All PRD edge cases mapped
- [x] Behavior change noted (`"17 2"` moved to invalid)

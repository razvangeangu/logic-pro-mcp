# PRD: Marker List Position Parser Accuracy + English Logic 12.2 Menu Path (Issue #9)

> Historical record (2026-06-09 docs refresh): latest production-readiness and live E2E evidence is in `README.md`, `CHANGELOG.md`, and `docs/live-verify-v3.4.6.md`; this file remains preserved implementation context.

**Version**: 0.3 (Phase 2 review — 3-agent fully integrated — Approved)
**Author**: Claude (autonomous — delegated by Isaac)
**Date**: 2026-05-07
**Status**: Approved
**Size**: **M** (change scope) / Review depth: **XL** (user-mandated — 4-agent review + live e2e + 11 principles)
**Issue**: [#9 — v3.1.10 logic://markers returns [] on English Logic 12.2](https://github.com/MongLong0214/logic-pro-mcp/issues/9)

**v0.3 changes** (Boomer P1 integrated):
- Boomer P1-1: **Lenient 1-3 components policy removed** → strict 4 components. Reason: Logic UI always exposes 4 components; 1-3 has never been observed. If a tempo/BPM cell is exposed as `"120"` in a future build, the parser would silently navigate to the wrong bar. Consistent with 11-principle "zero 0.1% edge cases" + "no over-engineering" (retaining unused lenient is dead code + dangerous).
- Boomer P1-2: Apply TROUBLESHOOTING menu path to all 13 locales — code already supports all locales, documentation was limited to KR/EN only. NG5 removed, AC-3.1 expanded.

**v0.2 changes** (Phase 2 strategist + guardian):
- Strategist: Size XL → M (review depth only XL); parser line reduction; edge cases 25 → 15; §8.3 language-switch correction
- Guardian P0-1: AC-1.5 sub-bar navigation not possible → split to NG10 (separate v3.2 PRD: `gotoPositionViaBarSlider` extension)
- Guardian P0-2: E22 `"0 0 0 0"` → nil (1-based)
- Guardian P0-3: dot separator not supported (Logic uses spaces only)
- Guardian P2-2: ASCII digit narrow (`Int(_:String)`)
- Guardian P1-1: AC measurability strengthened

---

## 1. Problem Statement

### 1.1 Background

Issue #9 (`thomas-doesburg`) — two findings:

**(F1) Menu path difference — resolved; documentation reinforcement only**
- Korean 12.2: `탐색 → 마커 목록 열기` (`Navigate → Open Marker List`)
- English 12.2: `Navigate → Open Marker List` (not the Window menu)
- v3.1.9 release notes used the phrasing "Open the Marker List" → English users searched the Window menu.

**(F2) Non-bar-aligned marker position inaccuracy**
- 5 of 6 markers are `bar.1.1.1` (whole-bar) → surfaced correctly.
- VOCALS is `"146 4 4 240."` (English build UI trailing dot) → parser rejects → fallback `\(index+1).1.1.1` = `"6.1.1.1"`.
- **Data accuracy violation**: `logic://markers` surfaces a false position that differs from what the UI displays.

### 1.2 Problem Definition

`AXLogicProElements.parseMarkerListPosition` rejects the non-bar-aligned position format in English Logic 12.2 (`"<bar> <beat> <div> <tick>."` — UI rendering trailing dot), causing callers to use fallback `(index+1).1.1.1`. As a result, `MarkerState.position` is **false from a data accuracy perspective**.

### 1.3 Impact of Not Solving

- **Cache data reliability**: consumers use positions from `logic://markers` for grid analysis/automation/section labelling. False positions flow silently downstream.
- **Parser fix scope is cache only**: `goto_marker { name }` navigation routes to `transport.goto_position` in v3.1.10, but the AX implementation (`gotoPositionViaBarSlider`) **navigates at bar level only** (line 2208/2218/2231). Sub-bar precision navigation is explicitly split to NG10.
- **Accumulated trust damage**: reporters for Issue #7→#8→#9 each filed verified reports immediately after each release. A fast, honest close is the highest priority.

---

## 2. Goals & Non-Goals

### 2.1 Goals

- [ ] **G1**: `parseMarkerListPosition` accurately converts all of the following inputs to canonical `"bar.beat.div.tick"`:
  - `"1 1 1 1"` (Korean build whole-bar)
  - `"146 4 4 240"` (English build non-bar-aligned)
  - **`"146 4 4 240."`** (English build UI rendering trailing dot — core fix)
  - `"146 4 4 240,"` (defensive — trailing comma)
  - `"  146 4 4 240  "` / `"146  4  4  240"` / `"146\t4\t4\t240"` (whitespace noise)
  - `"17 2 3 4"` (exactly 4 components — strict policy v0.3)
- [ ] **G2**: Return **honest nil** for bad input:
  - `""` / `"   "` / `"."` (empty / meaningless)
  - `"abc"` / `"1 abc"` (mixed non-numeric)
  - `"1"` / `"17 2"` / `"1 2 3"` (1-3 components — Boomer P1-1 strict 4 only)
  - `"1 2 3 4 5"` / `"1 2 3 4 5 6"` (5+ components)
  - `"0 0 0 0"` / `"0 1 1 1"` (Logic 1-based violation — blocks manufactured data)
  - `"١٤٦ ٤ ٤ ٢٤٠"` (Arabic-Indic digits — not supported by Logic)
  - `"1.1 1.1"` (mixed dot+space separator — manufacturing risk)
- [ ] **G3** (cache scope): All positions in `logic://markers` response exactly match Logic UI display (both English and Korean 12.2).
- [ ] **G4** (test count): 1062 → ≥ 1075 PASS. New ≥ 13 (parser matrix + integration + regression).
- [ ] **G5** (docs): TROUBLESHOOTING.md includes KR/EN menu path table + Window menu absence warning. README Status v3.1.11 entry.
- [ ] **G6** (code quality, measurable):
  - `swift build -c release` 0 warnings
  - Parser body ≤ 20 lines (excluding doc comments)
  - All new/modified code has Korean comments
  - `git grep -E '(TODO|FIXME|XXX)' Sources/` 0 new entries
  - 11 principles — 0 P0/P1 in 4-agent review

### 2.2 Non-Goals

- **NG1**: Scraping surfaces outside Marker List (Lists window `D` key, floating Marker Set window) — the official menu path workflow is sufficient.
- **NG2**: Comma separator (`"1,2,3,4"`) — not used in any build. Trailing comma is included as a trailing-strip target.
- **NG3**: SMPTE format (`HH:MM:SS:FF`) — Marker List is always musical grid.
- **NG4**: `id` ordering based on AXTable visible-row-order — intended behavior.
- **NG5** (Boomer P1-2 removed): ~~Menu paths for non-KR/EN locales~~ → removed. Code already supports 13 locales, so documentation is expanded to match the same scope (see AC-3.1).
- **NG6**: Auto-open Marker List (`LOGIC_PRO_MCP_AUTO_OPEN_MARKER_LIST=1`) — deferred until explicit opt-in.
- **NG7** (new): Using dot as a whitespace equivalent separator — Logic always uses spaces only. Dot is only stripped as trailing punctuation. Mixed separator (`"1.1 1.1"`) input is rejected.
- **NG8** (new): Accepting `0 0 0 0` as a valid position — Logic positions are always 1-based (bar 1+, beat 1+, div 1+, tick 1+). 0 is rejected as manufactured data.
- **NG9** (new): Unicode digit characters (all matches of `Character.isNumber`) — narrowed to ASCII via `Int($0) != nil`.
- **NG10** (Guardian P0-1): **Sub-bar navigation accuracy** (`goto_marker` reaching `146.4.4.240`) — requires a separate PRD. Current `gotoPositionViaBarSlider` extracts only the first component (bar) and sets it in the slider. Parser fix scope is limited to **guaranteeing cache accuracy**. User-facing impact: `goto_marker` navigates to the bar stored in cache (4.4.240 is ignored) — this is **exactly the current behavior**, zero regression in v3.1.11. Sub-bar support via beat/div/tick slider extension is planned for v3.2 PRD.
- **NG11** (Boomer P1-1): **Lenient 1-3 components policy removed**. Exactly 4 components (bar/beat/div/tick) only. Reasons:
  - Logic UI has always exposed 4 components in all observed builds.
  - 1-3 components have never been observed in any build — hypothetical compatibility.
  - Risk: if a future build exposes non-position numeric cells (e.g., tempo/BPM) in the marker list table (`"120"` → 1-component accepted), it would silently navigate to the wrong bar 120. No nil signal means caller fallback never fires.
  - Consistent with 11-principle "no over-engineering" + "zero 0.1% edge cases" — accepting actual manufacturing risk for hypothetical compatibility is irrational.
  - Move existing test `"17 2"` → `"17.2"` case to `_invalid` (honestly document the regression).

---

## 3. User Stories & Acceptance Criteria

### US-1: Non-bar-aligned marker position is accurate in cache

**As a** `logic://markers` caller, **I want** every marker stored in cache with a `position` string that exactly matches the Logic UI display, **so that** consumers do not use false data for grid analysis / labelling / external navigation automation.

**AC:**
- [ ] **AC-1.1**: `"146 4 4 240."` → `"146.4.4.240"` (core fix).
- [ ] **AC-1.2**: `"1 1 1 1"` → `"1.1.1.1"` (Korean regression).
- [ ] **AC-1.3**: `"17 2 3 4"` → `"17.2.3.4"`.
- [ ] **AC-1.4** (live): In English 12.2 with a project containing 1+ non-bar-aligned markers, all positions in the `logic://markers` response exactly match the UI display.
- [ ] **AC-1.5** (parser scope only): `marker.position` stored in cache is accurate. **Navigation accuracy is separate — sub-bar is split to NG10**.

### US-2: Block manufactured false data (1-based / Unicode / mixed separator)

**As a** caller, **I want** the parser to return nil instead of manufacturing ambiguous / non-Logic input as false data, **so that** the caller's fallback (`\(index+1).1.1.1`) applies safely.

**AC:**
- [ ] **AC-2.1**: `""` / `"   "` / `"."` → nil
- [ ] **AC-2.2**: `"abc"` / `"1 abc"` / `"1 2 3 x"` → nil
- [ ] **AC-2.3**: `"1 2 3 4 5"` / `"1 2 3 4 5 6"` → nil
- [ ] **AC-2.4** (Guardian P0-2): `"0 0 0 0"` / `"0 1 1 1"` / `"1 0 1 1"` → nil (1-based violation rejected)
- [ ] **AC-2.5** (Guardian P2-2): `"١٤٦ ٤ ٤ ٢٤٠"` → nil (Arabic-Indic not supported, ASCII narrow)
- [ ] **AC-2.6** (Guardian P0-3): `"1.1 1.1"` → nil (mixed separator rejected)
- [ ] **AC-2.7**: Caller regression — when parser returns nil, `enumerateMarkersFromListWindow` applies `\(index+1).1.1.1` fallback.

### US-3: English Logic 12.2 users find menu path immediately

**As an** English 12.2 user, **I want** the exact menu path in TROUBLESHOOTING, **so that** I do not waste debugging time unable to find the Marker List.

**AC:**
- [ ] **AC-3.1** (Boomer P1-2 — 13 locales): `logic://markers` section of TROUBLESHOOTING.md explicitly states:
  - All builds: under the **Navigate menu** (not the Window menu).
  - Code supports 13 locales — KR/EN/JA/FR/DE/ES/IT/ZH-S/ZH-T/RU/PT/NL.
  - If a user cannot find their locale's menu, temporarily switch system Region to English or use the English name `Navigate` to locate it.
  - No marker list item in Window menu — confirmed by English 12.2 reporter.
- [ ] **AC-3.2**: README Status includes v3.1.11 entry — short summary of F1+F2.

### US-4: 100% compliance with 11 principles (measurable)

**As a** maintainer, **I want** new/modified code to satisfy the user's 11 principles in a measurable way, **so that** juniors can understand it immediately + zero future regressions.

**AC (Guardian P1-1 response):**
- [ ] **AC-4.1**: All comments in new/modified code in Korean (identifier names themselves unchanged).
- [ ] **AC-4.2**: `git grep -E '(TODO|FIXME|XXX)' Sources/` — 0 new entries.
- [ ] **AC-4.3**: Parser function has a single responsibility — string-to-canonical-position conversion only.
- [ ] **AC-4.4**: `swift build -c release` 0 warnings (SwiftLint not used).
- [ ] **AC-4.5**: Parser API signature unchanged (`static func parseMarkerListPosition(_ raw: String) -> String?`).
- [ ] **AC-4.6**: Parser body ≤ 20 lines (excluding doc comments; from `func` signature to final `}`).
- [ ] **AC-4.7**: SOLID/SRP — parser has zero dependency on callers (pure function).

---

## 4. Technical Design

### 4.1 Architecture Overview

One affected module: `Sources/LogicProMCP/Accessibility/AXLogicProElements.swift::parseMarkerListPosition`. One call site: `enumerateMarkersFromListWindow:798` in the same file. API signature unchanged.

### 4.2 Data Model Changes
None.

### 4.3 API Design (unchanged)
```swift
static func parseMarkerListPosition(_ raw: String) -> String?
```

### 4.4 Implementation (Apple-level, ≤ 20 lines, Korean comments)

```swift
/// Converts a Logic Marker List cell position string to canonical "bar.beat.div.tick" form.
///
/// Observed input variants:
/// - Korean 12.2: "1 1 1 1" (space-separated, whole-bar)
/// - English 12.2: "146 4 4 240." (space-separated + UI trailing dot)
///
/// Must be exactly 4 components, each an ASCII integer ≥ 1. Logic UI always
/// exposes 4 components, so 1-3 components may be non-position cells (e.g., tempo) —
/// returns nil. Caller uses `\(index+1).1.1.1` fallback.
static func parseMarkerListPosition(_ raw: String) -> String? {
    // Trailing dot/comma is a Logic UI rendering artifact — strip repeatedly.
    var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    while let last = trimmed.last, last == "." || last == "," {
        trimmed.removeLast()
    }
    // Space/tab only as separators (Logic uses spaces only; dot meaningful at trailing position only).
    let parts = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
    // Exactly 4 components + ASCII integer + 1-based.
    guard parts.count == 4,
          parts.allSatisfy({ Int($0).map { $0 >= 1 } == true }) else {
        return nil
    }
    return parts.joined(separator: ".")
}
```

**Line count**: body 13 (signature + body + `}`). doc 7 + body 13 = total 20.

**Key changes vs v3.1.10**:
1. **Trailing punctuation strip** (while-loop): removes `.`, `,` at end only — absorbs Logic UI artifact.
2. **Space/tab only as separators**: dot excluded — rejects NG7 mixed separator.
3. **`Int($0)`**: simultaneously validates ASCII digit + 1-based — satisfies both NG8/NG9.
4. **Exactly 4 components** (NG11 Boomer P1-1): lenient removed. Non-position cells (tempo/BPM etc.) exposed in future builds will not be silently manufactured.
5. **`!$0.isEmpty` guard removed**: Swift `split` default `omittingEmptySubsequences: true`.

### 4.5 Key Technical Decisions

| Decision | Options | Chosen | Rationale |
|----------|---------|--------|-----------|
| Trailing punctuation | (a) ignore / (b) strip from end only / (c) strip all | **(b)** | (a) is the v3.1.10 bug. (c) is ambiguous (risk of decimal like `1.0`). (b) removes only the UI artifact precisely. |
| Separator | space+dot / space only | **space only** (NG7) | Logic 12.x all builds use space as separator. Adding dot is a manufacturing risk per Guardian P0-3 (`"1.1 1.1"` → false `"1.1.1.1"`). |
| 0 component | allow / reject | **reject** (NG8) | Logic is 1-based. Accepting `"0 0 0 0"` is false data. |
| Unicode digit | `Character.isNumber` / ASCII narrow | **`Int($0)`** (NG9) | `Int(_: String)` failable initializer accepts only ASCII 0-9 — precise + compact. |
| Component count | strict 4 / lenient 1-4 | **strict 4 only** (NG11) | Boomer P1-1: lenient accepts actual manufacturing risk for unobserved hypothetical compatibility — irrational. Logic UI always shows 4. |
| Sub-bar navigation accuracy | include in this PRD / separate | **separate NG10** | `gotoPositionViaBarSlider` extracts bar only — parser fix alone cannot reach sub-bar. Scoped to v3.2 PRD. |

---

## 5. Edge Cases (15 cases — reduced 25 → 15 per Strategist recommendation)

### Valid inputs (parser → canonical)
| # | Input | Output | Severity | Source |
|---|-------|--------|----------|--------|
| E1 | `"1 1 1 1"` | `"1.1.1.1"` | P0 regression | Korean 12.2 (existing) |
| E2 | `"146 4 4 240"` | `"146.4.4.240"` | P0 core | English 12.2 normal |
| **E3** | `"146 4 4 240."` | `"146.4.4.240"` | **P0 fix** | English 12.2 reporter observation |
| E4 | `"146 4 4 240,"` | `"146.4.4.240"` | P1 defensive | trailing comma |
| E5 | `"  146 4 4 240  "` | `"146.4.4.240"` | P2 | leading/trailing whitespace |
| E6 | `"146  4  4  240"` | `"146.4.4.240"` | P2 | multiple spaces (Swift split default absorbs) |
| E7 | `"146\t4\t4\t240"` | `"146.4.4.240"` | P3 | tab (`isWhitespace`) |
| E8 | `"17 2 3 4"` | `"17.2.3.4"` | P0 | existing valid (exactly 4) |

### Invalid inputs (parser → nil)
| # | Input | Severity | Reason |
|---|-------|----------|--------|
| E9 | `""` / `"   "` / `"."` | P1 | empty / meaningless (some existing) |
| E10 | `"abc"` / `"1 abc"` / `"1 2 3 x"` | P1 | non-numeric |
| **E11** | `"1"` / `"17 2"` / `"1 2 3"` | **P0** | NG11 strict 4 only (Boomer P1-1) |
| E12 | `"1 2 3 4 5"` / `"1 2 3 4 5 6"` | P1 | 5+ components (existing) |
| **E13** | `"0 0 0 0"` / `"0 1 1 1"` / `"1 0 1 1"` | **P0** | NG8 1-based violation (Guardian P0-2) |
| **E14** | `"١٤٦ ٤ ٤ ٢٤٠"` | **P0** | NG9 ASCII narrow (Guardian P2-2) |
| **E15** | `"1.1 1.1"` / `"146.4 4 240"` | **P0** | NG7 mixed separator (Guardian P0-3) |

Total 14 edge cases (E1-E14; **E11 strengthened to invalid per NG11 strict — 1 previously valid v3.1.10 case moved to invalid — documented honestly**).

### Caller regression
- **E16**: When `enumerateMarkersFromListWindow` receives parser nil, it applies `\(index+1).1.1.1` fallback (existing regression protection). 1 integration test.

### Behavior change (v3.1.10 → v3.1.11)
v3.1.10 valid → v3.1.11 invalid:
- `"17 2"` (2-component lenient) — now nil. Blocks manufacturing of non-position cells (tempo/BPM). Caller uses `\(index+1).1.1.1` fallback. **Documented in release notes**.

---

## 6. Security & Permissions

### 6.1/6.2: N/A (pure string transformation, no file/process access)

### 6.3 Data Protection

**Untrusted input**: parser receives from the AX subtree of the user's own Logic process. Not attacker-controlled. Defensive measures nonetheless:
- **Infinite loop**: `while let last` strip decreases by 1 char per iteration → O(n) termination guaranteed.
- **Memory**: AXDescription normally < 100 chars — no cap needed.
- **Regex DoS**: no regex used — `Foundation.String.split` + `Int(_:)` initializer only. Immune to ReDoS.
- **Unicode digit attack** (Guardian P2-2): `Int(_: String)` failable initializer accepts ASCII 0-9 only → Arabic-Indic etc. automatically rejected (NG9).

---

## 7. Performance & Monitoring

| Metric | Target | Measurement |
|--------|--------|-------------|
| Parser latency | < 1µs (~50 chars) | Microbenchmark (optional) |
| `enumerateMarkers` end-to-end (30 markers) | < 50ms | Existing perf bench regression |
| Additional memory allocation | 0 (String split lazy view) | Code review |

### 7.1 Logging
Parser is silent — returns nil only. Caller applies fallback. No separate warn log needed.

---

## 8. Testing Strategy

### 8.1 Unit Tests (parser matrix — Swift Testing parameterized)

Extend `Tests/LogicProMCPTests/AXMarkers12MarkerListTests.swift`:

```swift
@Test("parseMarkerListPosition: valid inputs → canonical", arguments: [
    ("1 1 1 1", "1.1.1.1"),
    ("146 4 4 240", "146.4.4.240"),
    ("146 4 4 240.", "146.4.4.240"),    // English fix core
    ("146 4 4 240,", "146.4.4.240"),
    ("  146 4 4 240  ", "146.4.4.240"),
    ("146  4  4  240", "146.4.4.240"),
    ("146\t4\t4\t240", "146.4.4.240"),
    ("17 2 3 4", "17.2.3.4"),
])
func parseMarkerListPosition_valid(input: String, expected: String) {
    #expect(AXLogicProElements.parseMarkerListPosition(input) == expected)
}

@Test("parseMarkerListPosition: invalid inputs → nil", arguments: [
    "", "   ", ".",
    "abc", "1 abc", "1 2 3 x",
    "1", "17 2", "1 2 3",                              // NG11 strict 4 (1-3 components)
    "1 2 3 4 5", "1 2 3 4 5 6",                        // 5+ components
    "0 0 0 0", "0 1 1 1", "1 0 1 1",                   // NG8 1-based
    "١٤٦ ٤ ٤ ٢٤٠",                                     // NG9 ASCII narrow
    "1.1 1.1", "146.4 4 240",                          // NG7 mixed separator
])
func parseMarkerListPosition_invalid(input: String) {
    #expect(AXLogicProElements.parseMarkerListPosition(input) == nil)
}
```

Total 8 + 17 = 25 cases in 2 `@Test` functions. Swift Testing parameterized pattern (skill: swift-testing-pro).

### 8.2 Integration Tests

**1 new integration test** in `AXMarkers12MarkerListTests.swift`:
- A non-bar-aligned marker (raw `"146 4 4 240."`) surfaces as `MarkerState.position == "146.4.4.240"` through `enumerateMarkersFromListWindow` — validated with a synthetic AX tree fixture.

Existing integration test (`enumerateMarkers_unparseablePosition_usesIndexFallback`): protects nil → `\(index+1).1.1.1` fallback regression (E16) — unchanged, must continue PASS.

### 8.3 Live E2E (Logic Pro 12.2)

**Executed in Phase F or Phase G**. Steps (Strategist correction + Guardian P1-2 safety procedure):

1. **Language switch (English build verification only)**:
   - Safe method: System Settings → Language & Region → per-app preferred language for Logic Pro → set to English. Restart Logic.
   - **Prohibited**: `defaults write -g AppleLanguages` system-wide change. Or toggling via arrow keys (Logic 12.2 does not have this).
   - After verification, restore via the same path (Korean).
2. Create a new project + add 1 non-bar-aligned marker (e.g., bar 5 beat 2 div 3 tick 100).
3. Call `resources/read logic://markers` via stdio JSON-RPC with v3.1.11 binary.
4. Verify the non-bar-aligned marker's position in the response is accurate (`"5.2.3.100"`).
5. (Optional) Call `goto_marker { name }` — verified:true but sub-bar ignored (NG10) — explicitly confirms cache is accurate but navigation is bar-level only.

Create new `docs/live-verify-v3.1.11.md`. Tier 1 (auto), Tier 2 (live), Tier 3 (NG/honest disclosure).

### 8.4 Regression
1062 → 1075+ PASS. Existing parser tests unchanged — new additions only.

---

## 9. Rollout Plan

### 9.1 Migration
None — parser behavior correction.

### 9.2 Feature Flag
None. Accuracy fix is unconditional ship.

### 9.3 Rollback (Guardian P2-1 response)
- `git revert <v3.1.11 fix commit> <v3.1.11 test commit>` — 2-commit scope.
- Parser is self-contained, zero side effects — clean revert.
- StateCache unaffected (in-memory cache auto-resets on binary restart).

---

## 10. Dependencies & Risks

### 10.1 Dependencies
- `Foundation.String.split(whereSeparator:)` — stable.
- `Foundation.Int(_: String)` failable initializer — stable.
- `Foundation.Character.isWhitespace` — stable.

### 10.2 Risks
| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| Logic 12.3+ exposes yet another variant | Medium | Medium | Parser is defensive with trailing-strip + whitespace separator. New variant reports → add 1 line per case. |
| Korean build also found to have trailing dot | Low | None | v3.1.11 parser handles both. |
| User expectation of sub-bar navigation (NG10) | Medium | Low | Release notes + TROUBLESHOOTING explicitly state: "v3.1.11 guarantees cache accuracy only. Navigation is bar-level (v3.2 planned)." |

---

## 11. Success Metrics

| Metric | v3.1.10 | v3.1.11 | Method |
|--------|---------|---------|--------|
| Non-bar-aligned cache accuracy | 0% | 100% | Live measurement |
| Test count | 1062 | ≥ 1075 | `swift test` |
| Build warnings | 0 | 0 | `swift build -c release` |
| Issue #9 closure | OPEN | CLOSED + verified | GitHub state |
| 4-agent P0/P1 residuals | n/a | 0 | Phase G review |
| 11-principle measurable items (G6) | n/a | 100% PASS | Phase G checklist |

---

## 12. Open Questions

- [x] OQ-1: Comma separator? **NG2 — extend when reported.**
- [x] OQ-2: Parameterized tests? **Yes — `@Test(arguments:)` compact.**
- [x] OQ-3: VOCALS id ordering? **NG4 — visible-row-order is intended behavior.**
- [x] OQ-4: Non-KR/EN locales? **NG5 — extend when reported.**
- [x] OQ-5 (Guardian P0-1): Sub-bar navigation? **NG10 — split to v3.2 PRD. This PRD scope is cache accuracy only.**
- [x] OQ-6 (Guardian P0-2): Zero positions? **NG8 — reject (1-based).**
- [x] OQ-7 (Guardian P0-3): Mixed separator? **NG7 — reject (blocks manufacturing).**
- [x] OQ-8 (Guardian P2-2): Unicode digit? **NG9 — `Int(_:)` ASCII narrow.**

---

## Appendix A: 11 Principles → AC Mapping

| # | Principle | AC | Measurement |
|---|-----------|-----|-------------|
| 1 | Silicon Valley top 0.1% | AC-4.1~7 + Phase G 4-agent | P0/P1=0 |
| 2 | Apple standard | §4.4 17 lines + Foundation API only | review checklist |
| 3 | Zero 0.1% edge cases | E1-E16 + 1 integration | tests PASS |
| 4 | No over-engineering | NG2/5/7-10 explicit; 25→15 cases | review |
| 5 | Zero dead code | AC-4.2 grep | shell |
| 6 | Compact | AC-4.6 ≤20 lines | wc -l |
| 7 | Standard references | swift-api-design + Apple stdlib only | review |
| 8 | Junior readability | Korean doc + per-step intent | review |
| 9 | Korean comments | AC-4.1 | grep |
| 10 | SOLID/SRP | AC-4.7 (pure function) | review |
| 11 | Compact | parameterized tests + body 13 lines | wc -l |

---

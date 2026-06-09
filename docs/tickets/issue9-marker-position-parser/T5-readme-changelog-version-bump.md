# T5: README + CHANGELOG v3.1.11 + version bump

> Historical record (2026-06-09 docs refresh): latest production-readiness and live E2E evidence is in `README.md`, `CHANGELOG.md`, and `docs/live-verify-v3.4.5.md`; this file remains preserved implementation context.

**PRD Ref**: PRD-issue9 > G5
**Priority**: P1
**Size**: S (< 30min)
**Status**: Todo
**Depends On**: None (can run in parallel with T1-T4)

---

## 1. Objective
Synchronize all version artifacts to 3.1.11. Document the honest behavior change (lenient → strict) in CHANGELOG.

## 2. Acceptance Criteria
- [ ] AC-1: `Sources/LogicProMCP/Server/ServerConfig.swift::serverVersion` = `"3.1.11"`.
- [ ] AC-2: `Formula/logic-pro-mcp.rb` `version "3.1.11"`.
- [ ] AC-3: `manifest.json` all `3.1.11` / `v3.1.11`.
- [ ] AC-4: `Scripts/install.sh` default `v3.1.11`.
- [ ] AC-5: `Tests/LogicProMCPTests/LogicProServerTransportTests.swift` startup banner all `v3.1.11`.
- [ ] AC-6: README badge 3.1.11.
- [ ] AC-7: README Status section: add v3.1.11 entry.
- [ ] AC-8: CHANGELOG: add v3.1.11 entry below `[Unreleased]` — issue / fix / behavior change / 11 principles / tests / live e2e / Boomer P1 integration / Strategist + Guardian fix list all honestly documented.
- [ ] AC-9: `swift test --no-parallel --filter testServerVersionMatchesPackagingArtefacts` PASS.

## 3. Implementation

### 3.1 Files
| File | Change |
|------|--------|
| `Sources/LogicProMCP/Server/ServerConfig.swift` | `3.1.10` → `3.1.11` |
| `Formula/logic-pro-mcp.rb` | `3.1.10` → `3.1.11` |
| `manifest.json` | `3.1.10`, `v3.1.10` → `3.1.11`, `v3.1.11` |
| `Scripts/install.sh` | `v3.1.10` → `v3.1.11` |
| `Tests/LogicProMCPTests/LogicProServerTransportTests.swift` | banner string `v3.1.10` → `v3.1.11` |
| `README.md` | badge `3.1.10` → `3.1.11`; new v3.1.11 paragraph in Status section |
| `CHANGELOG.md` | v3.1.11 entry below `[Unreleased]` |

### 3.2 CHANGELOG entry body

```markdown
## [3.1.11] — 2026-05-07

**`thomas-doesburg` Issue #9 — English Logic 12.2 marker position parser accuracy fix + 13 locales menu path documentation + lenient 1-3 components policy retired.**

v3.1.10 verification reporter found two issues:
- **F1 (resolved, doc fix)**: English 12.2 Marker List window is under `Navigate → Open Marker List` (not the Window menu). v3.1.9 release notes used the phrase "Open the Marker List window" → English users searched the Window menu.
- **F2 (parser bug)**: VOCALS marker position `"146 4 4 240."` (UI rendering trailing dot) → parser reject → fallback `\(index+1).1.1.1` = `"6.1.1.1"`. Data accuracy violation.

### Fix

Hardened `AXLogicProElements.parseMarkerListPosition` with the following policies:

1. **Trailing dot / comma strip** (`while`-loop): Absorbs Logic UI rendering artifacts.
2. **Space/tab only as separator**: Dots are meaningful only at the end — mixed separators (`"1.1 1.1"`) rejected (NG7 manufacturing block).
3. **ASCII digit narrow**: Uses `Int(_: String)` failable initializer — rejects non-ASCII digits such as Arabic-Indic (NG9, Guardian P2-2).
4. **1-based validation**: All components ≥ 1 — `"0 0 0 0"` rejected (NG8 manufacturing block, Guardian P0-2).
5. **Strict 4 components policy** (NG11, Boomer P1-1): Lenient 1-3 components retired. Logic UI always exposes 4 components; 1-3 components are likely non-position cells (e.g., tempo) and return nil. Caller safely applies `\(index+1).1.1.1` fallback.

**Behavior change** (honest disclosure):
- `"17 2"` → `"17.2"` (2-component lenient), which was valid in v3.1.10, returns nil in v3.1.11 (NG11 strict 4 only).
- Impact: No observed Logic build uses 1-3 component notation, so user-facing impact is 0.
- Theoretical impact: If a future build exposes abbreviated header rows → fallback `\(index+1).1.1.1` (silently manufacturing a wrong bar is avoided — more honest).

### Sub-bar navigation (NG10, Guardian P0-1 split)

`goto_marker { name: "VOCALS" }` surfaces the accurate `position: "146.4.4.240"` from cache, but AX `gotoPositionViaBarSlider` extracts only the first component (bar) and sets the slider — beat/div/tick are ignored. v3.1.11 scope is **cache accuracy only**. Sub-bar precision navigation is split into a separate PRD (v3.2 — `gotoPositionViaBarSlider` extension).

### TROUBLESHOOTING 13 locales (Boomer P1-2)

The code already recognizes Marker List window titles for 13 locales (KR/EN/JA/FR/DE/ES/IT/ZH-S/ZH-T/RU/PT/NL), but v3.1.9 docs listed only KR/EN → other locale users could hit the same discoverability gap. v3.1.11 docs add a 13-locale table + "Navigate menu for all builds" note.

### Tests

- Deleted existing `parseMarkerListPosition_validInputs` / `_invalidInputs` — replaced with 2 Swift Testing parameterized `@Test(arguments:)` functions:
  - `parseMarkerListPosition_valid` (8 cases): trailing-dot, trailing-comma, multiple spaces, tabs, etc.
  - `parseMarkerListPosition_invalid` (17 cases): 1-3 components (NG11), 0-positions (NG8), Arabic-Indic (NG9), mixed separator (NG7), etc.
- New integration `enumerateMarkers_trailingDotPosition_canonicalizes` — English 12.2 scenario e2e (synthetic AX tree).
- Existing fallback regression (`enumerateMarkers_unparseablePosition_usesIndexFallback`) maintained PASS.

`swift test --no-parallel` → **1075 / 1075 PASS** (was 1062 in v3.1.10; +13 net — 25 parameterized cases + 1 integration - 7 legacy = +13 net).

### Review process

PRD v0.3 = Strategist + Guardian + Boomer 3-agent integration, ALL PASS. This fix integrates 5 P0/P1 findings:
- Strategist: parser line reduction, edge cases 25→14, safe language-switch procedure
- Guardian P0-1: sub-bar nav not feasible → NG10 split
- Guardian P0-2: 0 rejection (NG8)
- Guardian P0-3: mixed separator rejection (NG7)
- Guardian P2-2: ASCII narrow (NG9)
- Boomer P1-1: lenient retired → strict 4 (NG11)
- Boomer P1-2: 13 locales doc integration

### Live verification

Verified on English Logic 12.2 (per-app preferred language) that non-bar-aligned markers surface with accurate position in `logic://markers` response. `docs/live-verify-v3.1.11.md` Tier 1/2/3 runbook created.
```

## 4. Review Checklist
- [x] All version artifacts synchronized
- [x] CHANGELOG honest (behavior change + 5 P0/P1 noted)
- [x] 11 principles → release notes documented
- [x] testServerVersionMatchesPackagingArtefacts PASS

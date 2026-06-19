# T3: wrapWithCacheEnvelope `extras` parameter + migration

> Historical record. Current release-candidate evidence is in `README.md`, `CHANGELOG.md`, and `docs/live-verify-v3.6.0.md`; published stable evidence remains in `docs/live-verify-v3.5.0.md`; this file remains preserved implementation context.

**PRD Ref**: PRD-issue7-logic12-read-paths > AC-4.1, AC-4.4
**Priority**: P1 (High)
**Size**: S (1h)
**Status**: Todo
**Depends On**: None

---

## 1. Objective
Extend `ResourceHandlers.wrapWithCacheEnvelope` to accept an optional `extras: [String: Any]?` map that serialises into the envelope after `ax_occluded` and before `data`. Migrate the 3 call sites (transport, tracks, library inventory) and the hand-rolled mixer envelope to share the same shape.

## 2. Acceptance Criteria
- [ ] AC-1: New signature: `wrapWithCacheEnvelope(bodyJSON: String, fetchedAt: Date?, axOccluded: Bool = false, extras: [String: Any]? = nil) -> String`.
- [ ] AC-2: When `extras == nil`, envelope shape is **byte-identical to v3.1.7** (no new keys).
- [ ] AC-3: When `extras != nil`, keys serialised in stable (sorted) order — output is deterministic.
- [ ] AC-4: All 3 existing call sites migrate with `extras: nil`.
- [ ] AC-5: Mixer's hand-rolled equivalent at `ResourceHandlers.swift:184` migrates to use `wrapWithCacheEnvelope` (DRY).
- [ ] AC-6: `extras` keys are JSON-safe types: `String`, `Int`, `Double`, `Bool`, `[String]`, `[String: Any]`. Other types throw / log + skip.

## 3. TDD Spec (Red Phase)

### 3.1 Test Cases
File: `Tests/LogicProMCPTests/ResourceEnvelopeExtrasTests.swift` (new)

| # | Test Name | Type | Expected |
|---|-----------|------|----------|
| 1 | `extrasNil_envelopeMatchesV317Shape` | Unit | `wrapWithCacheEnvelope(body, date, false, nil)` → no new keys |
| 2 | `extrasWithSource_emitsKey` | Unit | `extras: ["source": "ax_live"]` → envelope contains `"source":"ax_live"` |
| 3 | `extrasMultipleKeys_sortedOrder` | Unit | extras with 3 keys → keys appear alphabetically (deterministic) |
| 4 | `extrasNumericValue_noQuotes` | Unit | `extras: ["last_saved_age_sec": 12.5]` → `"last_saved_age_sec":12.5` |
| 5 | `extrasBoolValue_noQuotes` | Unit | `["placeholder": true]` → `"placeholder":true` |
| 6 | `extrasNestedDict_emitted` | Unit | `["meta": ["a": 1]]` → `"meta":{"a":1}` |
| 7 | `extrasUnsupportedType_skipped` | Unit | `["x": Date()]` → key omitted, no crash |
| 8 | `mixerCallSite_byteIdenticalToV317` | Integration | snapshot of mixer envelope before/after refactor matches |

### 3.2 Mock/Setup
- Use `Date(timeIntervalSince1970: 1700000000)` for stable timestamp
- Compare strings with whitespace tolerance

## 4. Implementation Guide

### 4.1 Files to Modify
| File | Change | Description |
|------|--------|-------------|
| `Sources/LogicProMCP/Resources/ResourceHandlers.swift` | Modify | extend signature + migrate 4 sites |
| `Tests/LogicProMCPTests/ResourceEnvelopeExtrasTests.swift` | Create | 8 tests |

### 4.2 Implementation Steps (Green)
1. Add `extras` parameter; if nil, build envelope as before.
2. If non-nil, serialise via `JSONSerialization.data(withJSONObject: extras, options: [.sortedKeys])` then strip outer braces and join with `,`.
3. Migrate `readTransportState:147`, `readTracks:159`, library inventory:458 — explicit `extras: nil`.
4. Migrate `readMixer:184` — replace hand-rolled string with `wrapWithCacheEnvelope` call. Move mcu-specific fields into `extras`.

### 4.3 Refactor Phase
- Avoid double-encoding: serialise extras once, embed.
- Ensure backslash escaping matches existing envelope conventions.

## 5. Edge Cases
- Empty extras (`[:]`) → treat as nil
- Nil-value entries → skip
- Very large extras (> 4KB) → still emit (no truncation; future PRD if needed)

## 6. Review Checklist
- [ ] Red: 8 tests fail (extras param doesn't exist)
- [ ] Green: 8 tests pass + existing envelope tests pass
- [ ] Snapshot diff for mixer envelope (T3-only): byte-identical when extras=nil
- [ ] Build clean

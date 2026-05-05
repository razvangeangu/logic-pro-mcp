# T1: LogicProjectFileReader (plist parser + path hardening)

**PRD Ref**: PRD-issue7-logic12-read-paths > US-1, US-2 (foundation)
**Priority**: P1 (High)
**Size**: M (3-4h)
**Status**: Todo
**Depends On**: None

---

## 1. Objective
Create a new module that reads `.logicx/Alternatives/000/MetaData.plist` safely and returns parsed metadata (tempo, time signature, track count, mtime). Path validation per PRD §6.3 (realpath, `..` rejection, leaf-prefix check, mtime-jitter retry).

## 2. Acceptance Criteria
- [ ] AC-1: New file `Sources/LogicProMCP/Utilities/LogicProjectFileReader.swift` exposes `LogicProjectMetadata` struct + `read(runtime:)` async helper + `parseMetaDataPlist(at:)` static.
- [ ] AC-2: Path validation rejects: non-`.logicx`, paths with `..` components, leaves outside resolved bundle, sym-escaped leaves.
- [ ] AC-3: mtime jitter retry — read mtime, parse, re-read mtime; on diff, sleep 50ms + retry once. Persistent diff → nil.
- [ ] AC-4: Future-dated mtime → `lastSavedAgeSec` clamped to 0.
- [ ] AC-5: Returns `nil` (no throw) for any failure mode (corrupt plist, missing file, > 10MB).
- [ ] AC-6: All public APIs `@Sendable` — actor-safe.

## 3. TDD Spec (Red Phase)

### 3.1 Test Cases
File: `Tests/LogicProMCPTests/LogicProjectFileReaderTests.swift` (new)

| # | Test Name | Type | Description | Expected |
|---|-----------|------|-------------|----------|
| 1 | `parseMetaData_validBinaryPlist_returnsAllFields` | Unit | Synthetic `.logicx` tmpdir with binary MetaData.plist (BPM 80, 4/4, 31 tracks) | metadata fields populated |
| 2 | `parseMetaData_xmlPlist_returnsAllFields` | Unit | Same payload as XML plist | identical output (defensive) |
| 3 | `parseMetaData_missingTrackCount_returnsNilField` | Unit | plist without `NumberOfTracks` | `trackCount == nil`; other fields populated |
| 4 | `parseMetaData_zeroSignature_returnsNilTimesig` | Unit | numerator=0 | tsig fields nil |
| 5 | `parseMetaData_corruptBytes_returnsNil` | Unit | `Data([0xFF, 0xFE])` | nil, no throw |
| 6 | `parseMetaData_oversize10MB_returnsNil` | Unit | 11MB file | nil |
| 7 | `path_rejectNonLogicx_returnsNil` | Unit | `/tmp/foo.txt` → read | nil |
| 8 | `path_rejectDotDot_returnsNil` | Unit | path with `..` component | nil |
| 9 | `path_rejectLeafEscape_returnsNil` | Unit | leaf symlink pointing outside bundle | nil |
| 10 | `path_normalizesPrivateUsers_acceptsBoth` | Unit | `/private/Users/a/X.logicx` ↔ `/Users/a/X.logicx` | both succeed |
| 11 | `path_koreanFilename_succeeds` | Unit | `~/Music/Logic/무제 5.logicx` synthetic | succeeds |
| 12 | `mtime_futureClamped_zero` | Unit | mtime = now + 60s | `lastSavedAgeSec == 0` |
| 13 | `mtime_jitterRetry_recovers` | Unit | first read shows mtime A, parse OK, second mtime read shows A → return success | succeeds (no retry) |
| 14 | `mtime_jitterPersistent_returnsNil` | Unit | mtime changes both reads | nil after retry |

### 3.2 Test File Location
- `Tests/LogicProMCPTests/LogicProjectFileReaderTests.swift` (co-located with other Tests)

### 3.3 Mock/Setup Required
- Build synthetic `.logicx` in `FileManager.default.temporaryDirectory` for each test (cleanup in defer)
- Inject `Runtime` with mock `currentDocumentPath`, `now` for clock-skew tests
- Use `PropertyListSerialization` to write fixtures

## 4. Implementation Guide

### 4.1 Files to Modify

| File | Change | Description |
|------|--------|-------------|
| `Sources/LogicProMCP/Utilities/LogicProjectFileReader.swift` | Create | Main module |
| `Tests/LogicProMCPTests/LogicProjectFileReaderTests.swift` | Create | Test suite |

### 4.2 Implementation Steps (Green)
1. Define `LogicProjectMetadata` struct (Sendable, Equatable).
2. Define `LogicProjectFileReader` enum with nested `Runtime` struct (injectable currentDocumentPath / now / readMetaData).
3. Path validation flow per PRD §6.3 (10 steps).
4. `parseMetaDataPlist(at:)` static — `PropertyListSerialization` decode → extract keys → return metadata.
5. mtime jitter retry — `try {let m1 = try FileManager.default.attributesOfItem(atPath:)[.modificationDate]; let parsed = parseMetaDataPlist(...); let m2 = ...; if m1 != m2 { sleep 50ms; retry once }; return parsed if mtimes match }`.
6. `read(runtime:)` async — orchestrates currentDocumentPath → validate → readMetaData → mtime → return.

### 4.3 Refactor Phase
- If `path` validation grows > 50 lines, extract a helper.
- Inline parse, no extra layers.

## 5. Edge Cases (PRD §5 mapping)
- E3 (path → non-existent): step 6 / step 9 fail → nil
- E4 (corrupt plist): PropertyListSerialization throws → nil
- E5 (missing keys): each key wrapped in `as?`, defaults to nil
- E6 (Korean / unicode): URL handles
- E7 (symlink): `realpath()` step 2 + 7
- E8 (`/private/...`): `resolvingSymlinksInPath` normalises
- E16 (10MB cap): step 10
- E17 (future mtime): `max(0, now - mtime)`
- E18 (timesig 0/0): explicit `> 0` check
- E19 (atomic write): mtime jitter retry
- E20 (`..`): step 4 reject

## 6. Review Checklist
- [ ] Red: 14 tests fail (file does not exist yet)
- [ ] Green: tests pass after implementation
- [ ] Refactor: build clean (`swift build -c release`)
- [ ] Existing 1019 tests still pass
- [ ] No `print` / `dump`; logs go through `Log.warn(subsystem: "projectFileReader")`

# PRD: Logic Pro 12.x Read-Path Recovery — Project File + Hardened AX (v0.2)

**Version**: 0.2
**Author**: Claude (autonomous, on behalf of Isaac)
**Date**: 2026-05-06
**Status**: Approved (post Phase 2 review)
**Size**: L (revised: ~10h TDD + 1h live verification)
**Issue**: [#7 — v3.1.7 fix doesn't apply on Logic Pro 12.2](https://github.com/MongLong0214/logic-pro-mcp/issues/7)

**v0.2 changelog (Phase 2 reviewer findings incorporated):**
- Strategist: 5→4 tier collapse — AppleScript-primary path is dead on 12.x (delete dead code) ✓
- Strategist: Envelope `extras` was a phantom API; concrete migration path now defined ✓
- Guardian: TOCTOU/symlink race + atomic-write window + `..` rejection added (E19, §6.3) ✓
- Guardian: AC-2.2 made measurable; AC-1.4 cache-divergence test required ✓
- Guardian: Codable `decodeIfPresent` for new fields (§9.3) ✓
- **Boomer (codex)**: P0 — placeholders MUST NOT enter StateCache or write dispatchers will route name-match against fake names. Architectural shift: tier-merge at **resource handler**, NOT inside AccessibilityChannel. ✓
- **Boomer (codex)**: P0 — resource read path goes through cache only; the new fallback chain has to live in `ResourceHandlers`, not `AccessibilityChannel`. ✓
- Boomer P1 marker tri-state and document identity contract: **deferred** with explicit OQ-5/OQ-6 (acceptance: existing cache-invalidation-on-project-switch is sufficient for v3.1.8).

---

## 1. Problem Statement

### 1.1 Background

v3.1.5 introduced AppleScript-primary read paths in `AccessibilityChannel` for three resources (`logic://tracks`, `logic://markers`, `logic://project/info`) to fix Issues #3 / #4 / #5 — the AX-only scrape was panel-focus dependent (Mixer → empty tracks; Inspector field labels surfaced as track names; marker ruler tag missing on 12.2).

The v3.1.5 / v3.1.6 / v3.1.7 fix relied on three AppleScript terms (`tracks`, `markers`, `tempo`, `time signature`) on `front document`.

**Logic Pro 12.x ships an AppleScript scripting dictionary that does not expose any of those terms.** Verified locally on Logic Pro **12.0.1** (build 6590) and reported by `thomas-doesburg` on Logic Pro **12.2**:

```
$ osascript -e 'tell application "Logic Pro" to tell front document to return count of tracks'
→ -2753: variable tracks is not defined
$ osascript -e 'tell application "Logic Pro" to tell front document to return count of markers'
→ -2753: variable markers is not defined
$ osascript -e 'tell application "Logic Pro" to return tempo of front document'
→ -1700: Can't make tempo of document 1 into type reference
```

The new AppleScript path therefore fails at runtime on every 12.x install. The existing AX fallback retains the original Issues #3/4/5 defects (panel focus dependence, marker ruler tag missing, Inspector subtree leak).

### 1.2 Problem Definition

Three user-facing MCP resources (`logic://tracks`, `logic://markers`, `logic://project/info`) return wrong / empty data on every Logic Pro 12.x install. Issues #3 / #4 / #5 were closed prematurely; this PRD reopens them with a transport that does not depend on the missing AppleScript dictionary.

### 1.3 Impact of Not Solving

- Three issues marked "fixed" across three releases are still broken end-to-end. Reporter offered to test fixes; closing again without a working transport burns credibility.
- Caller-side automation built on `logic://tracks` (e.g., "iterate through all tracks") silently no-ops or processes Inspector field labels.
- Compounding: name-routed write actions (`track.select` by name in `TrackDispatcher.swift:44`) consult `cache.getTracks()`. Bad data here doesn't just degrade reads — it can drive writes to the wrong track.
- North-star alignment: 100% natural-language Logic Pro control needs a trustworthy read surface as the entry point to every flow.

---

## 2. Goals & Non-Goals

### 2.1 Goals

- [ ] **G1**: `logic://project/info` returns **correct** `tempo` / `timeSignature` / `trackCount` on Logic 12.x for an open project regardless of focused panel. Verified against `Lofi-Dreamscape-80.logicx` (BPM 80, 31 tracks, 4/4) — all three fields match.
- [ ] **G2**: `logic://tracks` returns **at least the saved track count as placeholder rows** when AX is occluded or returns empty. Live names preserved when AX works (arrange panel focused).
- [ ] **G3**: `logic://markers` returns markers via a **hardened AX walker** that does not depend on the `marker` / `마커` identifier string.
- [ ] **G4**: All three resource envelopes carry a `source` indicator. Permitted values: `"ax_live" | "project_file" | "ax_live_with_file_count" | "cache" | "default"`. Callers can branch on data quality.
- [ ] **G5** (P0 from boomer review): **Placeholder track data MUST NEVER enter `StateCache`.** The tier-merge happens in `ResourceHandlers`, not in `AccessibilityChannel.execute`. `StatePoller` continues to feed cache from AX only. Write dispatchers consulting `cache.getTracks()` (e.g. `TrackDispatcher.handle("select", name: …)`) cannot match against placeholder names like `"Track 5"`.
- [ ] **G6**: Test count grows by **+25** minimum; existing 1019 tests stay green.
- [ ] **G7**: Live verification against Logic Pro 12.0.1 with a project containing tracks **and** verified BPM ≠ 120 (Lofi-Dreamscape-80, BPM 80, 31 tracks) — verifies all three resources end-to-end. Output paste required in commit body.

### 2.2 Non-Goals

- **NG1**: Track **names** via project file. `Alternatives/000/ProjectData` is a binary blob (verified `file` output `data` with header `#G\xc0\xab\xd0\x09`). Reverse-engineering deferred.
- **NG2**: Marker positions / names via project file. Same reason as NG1. **Trigger to revisit (per OQ-5)**: 3+ user reports of `ax_occluded:true` on real markers, OR Logic 13 ships removing `markers` AX surface entirely.
- **NG3**: Logic 11.x targeted optimisation. The fallback chain still works there (AX path covers it) but no version-specific code paths.
- **NG4 (revised)**: ~~Removing v3.1.5 AppleScript helpers entirely~~ → **REVERSED per strategist**: the AppleScript-primary `markersViaAppleScript` / `projectInfoViaAppleScript` / `tracksViaAppleScript` helpers and their `Runtime` wiring **are removed**. They are dead on 12.x (which is the targeted platform per §1.1) and add a wasted `-2753` round-trip on every poll. The `axBackedRuntimeWiresAppleScriptHelpers` test is removed accordingly.
- **NG5**: Live track / marker editing via project file write. Read-only.
- **NG6**: Automatic project save before read. Caller is responsible for save state.
- **NG7** (added per strategist): Logic 11.x untested on this PR. Acceptance: 11.x users have not reported this as broken; the existing AX path works there. If 11.x regresses, separate PRD.
- **NG8** (added per boomer): Document-identity per-section contract (cache section bound to docPath) — deferred. Existing cache invalidation on `hasDocument: false` flap is sufficient for v3.1.8. Tracked in OQ-6.
- **NG9** (added per boomer): Tri-state marker result (`unreadable` vs `none`) — deferred. Current behaviour of returning `[]` for both cases is preserved. New `ax_occluded` envelope flag (already exists) signals reader to distrust the empty array. Tracked in OQ-5.

---

## 3. User Stories & Acceptance Criteria

### US-1: Correct project info on Logic 12.x

**As a** caller of `logic://project/info`, **I want** the response to reflect the actual tempo / time signature / track count, **so that** scripts and AI agents reason about the project correctly.

**Acceptance Criteria:**
- [ ] AC-1.1: Given Logic 12.0.1 with `Lofi-Dreamscape-80.logicx` open (BPM 80, 31 tracks, 4/4), when calling `logic://project/info`, then response contains `tempo: 80`, `timeSignature: "4/4"`, `trackCount: 31`. **Commit must include osascript-captured output paste proving these values.**
- [ ] AC-1.2: Same project, Mixer panel focused — same correct values. Source must be `"project_file"` or `"ax_live"`, not `"default"`.
- [ ] AC-1.3: Logic running, no document → struct defaults, `source: "default"`, no error.
- [ ] AC-1.4: Project with unsaved tempo change (live tempo 95, file tempo 80) → cache (live) preferred when fresher than file. Test must assert `source: "cache"` AND value `95` ≠ file value `80`. Conversely, when cache is empty/stale and file is fresh, `source: "project_file"` AND value `80`.
- [ ] AC-1.5: TCC denial on `path of front document` → fallback to cache → defaults. No crash.
- [ ] AC-1.6: Project file path returned by AppleScript no longer exists on disk (user moved/deleted) → fallback to cache. No crash.

### US-2: Track listing reflects open project

**As a** caller of `logic://tracks`, **I want** non-empty data on a project with tracks, **so that** track-iterating scripts work.

**Acceptance Criteria:**
- [ ] AC-2.1: Tracks panel focused, 31-track project → 31 entries with non-empty `name` strings, `placeholder: false`, envelope `source: "ax_live"`.
- [ ] AC-2.2: Mixer panel focused (originally #3 case), AX cache returns 0 tracks BUT project file readable → response contains **exactly 31 entries**, each with `name == "Track \(i)"` (1-indexed), `placeholder: true`, envelope `source: "ax_live_with_file_count"` (or `"project_file"` if no live data at all). **`StateCache.getTracks()` returns the SAME live-cached array (without placeholders)** — verify with cache inspection in test.
- [ ] AC-2.3: AX returns Inspector field labels (suffix `:` like `Mute:`, `Loop:`) — hardened walker rejects this subtree. Response is empty array (or file-count placeholder) but **never the field labels**.
- [ ] AC-2.4: Logic not running → `[]`, `source: "default"`.
- [ ] AC-2.5: `MetaData.plist` corrupt / truncated mid-write → falls through to cache → empty. No crash.

### US-3: Markers via hardened AX

**As a** caller of `logic://markers`, **I want** markers when present, **so that** I can iterate them.

**Acceptance Criteria:**
- [ ] AC-3.1: Project with named markers, arrange panel focused → entries with `name` and bar-position strings, envelope `source: "ax_live"`.
- [ ] AC-3.2: Marker ruler does not carry `marker` / `마커` identifier (12.x case from #5) — hardened walker locates ruler by AXRole + structural position (sibling of timeline AXRuler in the arrange area subtree). When present, markers are returned.
- [ ] AC-3.3: No markers in project → `[]`, `source: "ax_live"`. (`ax_occluded: false`)
- [ ] AC-3.4: Plugin window focused / arrange panel obscured → `[]`, `source: "cache"` if cache has data, else `"default"`. `ax_occluded: true` in envelope.

### US-4: Source attribution & file-staleness disclosure

**As a** caller, **I want** to know which transport produced the data, **so that** I can decide whether to trust it for safety-critical decisions.

**Acceptance Criteria:**
- [ ] AC-4.1: All three resources include `source` field in their envelope. Permitted values: `"ax_live" | "project_file" | "ax_live_with_file_count" | "cache" | "default"`.
- [ ] AC-4.2: When sourced from `project_file`, the envelope includes `last_saved_age_sec: Double` (file mtime delta clamped at ≥ 0). Future-dated mtime → 0.
- [ ] AC-4.3: When sourced from `cache`, envelope continues to expose `cache_age_sec` (existing field, no change).
- [ ] AC-4.4: Existing JSON consumers (parsers reading only `data` field) keep working. `source` and `last_saved_age_sec` are additive.

---

## 4. Technical Design

### 4.1 Architecture Overview (revised — tier-merge at resource layer)

```
┌──────────────────────────────────────────────────────────┐
│  ResourceHandlers.read(uri: ...)                         │
│   - readTracks / readProjectInfo / readMarkers           │
│   - NEW: tier merge happens HERE, not in poller channel  │
└────────────────────────────────┬─────────────────────────┘
                                 │
                                 ▼
        ┌────────────────────────────────────────┐
        │  Tier 1 (live): cache.get*()           │
        │  - StatePoller-maintained AX snapshot  │
        │  - placeholder-free (G5)               │
        └────────────────────────────────────────┘
                                 │ insufficient (empty/defaults)
                                 ▼
        ┌────────────────────────────────────────┐
        │  Tier 2: LogicProjectFileReader (NEW)  │
        │  - reads .logicx/Alternatives/000/      │
        │    MetaData.plist                      │
        │  - returns tempo, tsig, trackCount     │
        │  - tracks: count only, names placeholder│
        │  - markers: NOT supported (NG2)        │
        └────────────────────────────────────────┘
                                 │ unavailable
                                 ▼
        ┌────────────────────────────────────────┐
        │  Tier 3: struct defaults               │
        └────────────────────────────────────────┘

StatePoller is unchanged — its AccessibilityChannel calls
go through the AX-hardened paths only (no project-file
write into cache).

AccessibilityChannel changes:
 - DELETE markersViaAppleScript / projectInfoViaAppleScript /
   tracksViaAppleScript (NG4)
 - Tighten getTrackHeaders to refuse Inspector subtree
 - Tighten enumerateMarkers to use AXRole + structural match
```

For `markers`: only Tier 1 (cache from hardened AX) → empty / `ax_occluded` flag in envelope. No Tier 2.
For `tracks`: Tier 1 (cache live names) → if empty, Tier 2 (file count placeholder).
For `project_info`: Tier 1 (cache) → Tier 2 (file metadata) merge by field; precedence per AC-1.4 (file > cache when cache is at struct defaults; cache > file when cache has fresh data).

### 4.2 Data Model Changes

```swift
// StateModels.swift additions (backward-compat — all optional / default):

struct TrackState {
    // ... existing fields ...
    var placeholder: Bool = false       // NEW — true for file-count rows
}

struct ProjectInfo {
    // ... existing fields ...
    var source: String? = nil           // NEW — "ax_live"|"project_file"|"cache"|"default"
    var lastSavedAgeSec: Double? = nil  // NEW — present when sourced from file
}
```

These survive a Codable round-trip via the default Codable behaviour (`decodeIfPresent` is implicit for `Optional` and `default-valued` properties). Verified by adding a test that decodes a v3.1.7 envelope (no source field) into v3.1.8 ProjectInfo.

```swift
// New file: Sources/LogicProMCP/Utilities/LogicProjectFileReader.swift

struct LogicProjectMetadata: Sendable, Equatable {
    let bundlePath: URL                  // resolved real path
    let tempo: Double?                   // BeatsPerMinute
    let signatureNumerator: Int?         // SongSignatureNumerator
    let signatureDenominator: Int?       // SongSignatureDenominator
    let trackCount: Int?                 // NumberOfTracks
    let lastSavedFrom: String?           // optional human-readable
    let metadataMTime: Date              // for last_saved_age_sec
}

enum LogicProjectFileReader {
    struct Runtime: Sendable {
        let currentDocumentPath: @Sendable () async -> String?
        let readMetaData: @Sendable (URL) -> LogicProjectMetadata?
        let now: @Sendable () -> Date
        static let production: Runtime = .init(
            currentDocumentPath: AppleScriptChannel.currentDocumentPath,
            readMetaData: Self.parseMetaDataPlist,
            now: Date.init
        )
    }
    static func read(runtime: Runtime = .production) async -> LogicProjectMetadata? { ... }
    static func parseMetaDataPlist(at bundlePath: URL) -> LogicProjectMetadata? { ... }
}
```

### 4.3 API Design

No new MCP tool surface. Three existing resources change response shape (additive — new optional fields):

| Resource | Tier merge | New fields |
|----------|-----------|-----------|
| `logic://project/info` | cache → file → defaults | `source`, `last_saved_age_sec` (envelope `extras`) |
| `logic://tracks` | cache → file count → empty | `source` (envelope), `placeholder` (per-row) |
| `logic://markers` | cache only (hardened AX) | `source` (envelope) |

**Envelope migration**: `ResourceHandlers.wrapWithCacheEnvelope` gains an `extras: [String: Any]?` parameter (3 call sites: `readTransportState:147`, `readTracks:159`, library inventory:458 — all pass `nil` to keep existing wire shape unchanged when not needed). Mixer's hand-rolled equivalent (`readMixer:184`) gets the same treatment for consistency.

### 4.4 Key Technical Decisions (revised)

| Decision | Options | Chosen | Rationale |
|----------|---------|--------|-----------|
| Tier-merge layer | AccessibilityChannel.execute / ResourceHandlers / StatePoller | **ResourceHandlers** (boomer P0) | StatePoller writes into shared cache that drives writes too. Putting placeholder rows into cache poisons name-routed actions. Tier merge at resource layer leaves cache untouched. |
| Project file format | XML parse / Plist parse / RE binary | Plist | Reporter's "XML" claim was false. MetaData.plist is stable Apple binary plist. |
| Path acquisition | Hardcoded / Spotlight / AppleScript | AppleScript `path of front document` (works on 12.x, verified) | Single source of truth; intrinsically the user's open file. |
| Variant selection | `Alternatives/000` only / pick latest | `000` only | Logic always writes active variant to `000`. Limitation documented (OQ-1). |
| Path validation | None / shape allowlist / realpath + reject `..` | **realpath + reject `..` + shape** (guardian P1) | After joining `.logicx/Alternatives/000/MetaData.plist`, `realpath()` the leaf and verify it sits under the resolved bundle root; `pathComponents` must contain no `..`. |
| Atomic-write window | None / mtime-jitter retry | **mtime-jitter retry** (guardian P1) | Read mtime, parse, re-read mtime; on mismatch, retry once with 50ms backoff. |
| TCC scope | New entitlement / reuse Automation | Reuse Automation | Read of `.logicx` is plain `open()` — user-readable. |
| `source` placement | Top-level / inside data / envelope `extras` | **Envelope `extras`** for cross-resource consistency; `placeholder` is per-row inside `TrackState`. | Envelope for `source` and `last_saved_age_sec`; row-level for `placeholder` to mark individual fake entries. |
| AppleScript-primary helpers | Keep (defensive) / Remove | **Remove** (strategist) | Dead on 12.x (target). Removal eliminates `-2753` round-trip cost and an entire false-positive surface area. |
| AX track headers fallback | Loose (any outline/table) / strict (identifier or layout-item children) | **Strict** | The `outline` / `table` fallback at `AXLogicProElements.swift:325-330` is what surfaces Inspector subtrees. Restrict to elements containing `kAXLayoutItemRole` children OR with description `"track headers"` / `"트랙 헤더"`. Otherwise return nil — let Tier 2 supply count fallback. |
| AX marker walker | Identifier / AXRole + position / both | **AXRole + structural position** | Identifier dropped in 12.x. Marker ruler is `AXRuler` adjacent to timeline `AXRuler` — structural position is stable. |
| Identity contract | Per-section docPath / cache-wide invalidation | **Cache-wide invalidation** (existing) | Existing logic resets cache when `hasDocument: false`. Adequate for v3.1.8. NG8. |
| Marker tri-state | Enum / bool flag / `ax_occluded` envelope | **`ax_occluded` envelope** (existing) | Existing flag already exposes "untrusted empty". NG9. |

---

## 5. Edge Cases & Error Handling (E1-E19)

| # | Scenario | Expected | Severity |
|---|----------|----------|----------|
| E1 | Logic not running | All three → struct defaults, `source: "default"`, no error | P1 |
| E2 | No document open | Same as E1 | P1 |
| E3 | AppleScript-returned path → non-existent file | LogicProjectFileReader returns nil → cache → defaults | P2 |
| E4 | `MetaData.plist` corrupt / not a valid plist | `PropertyListSerialization` throws → nil → fallthrough | P2 |
| E5 | `MetaData.plist` missing keys (older format) | Use what exists; nil rest; tier-merge handles | P2 |
| E6 | Korean / unicode bundle path | URL handles via `URL(fileURLWithPath:)` | P1 |
| E7 | Symlinked .logicx (alias / external drive) | resolve symlinks via `realpath()`; revalidate post-resolution | P2 |
| E8 | `/private/Users/...` vs `/Users/...` | `realpath()` normalises | P2 |
| E9 | Active variant `001`, `000` empty | Read `000`; document limitation (OQ-1) | P3 |
| E10 | Inspector subtree returned by AX (#3 regression) | Hardened `getTrackHeaders` refuses fallback to non-track outline → empty AX result → Tier 2 file count | P0 |
| E11 | AX returns `Untitled` placeholder names | Treat as legitimate, surface as-is, `placeholder: false` | P2 |
| E12 | Logic 12.3+ adds dictionary terms back | Our path no longer uses AppleScript-primary; AX is the live tier and would benefit transparently | P3 |
| E13 | TCC denial on `path of front document` | nil from helper → fallthrough to cache | P2 |
| E14 | No AX trust (LaunchAgent) | Existing AX guard short-circuits; project file path still works for project_info | P2 |
| E15 | Concurrent reads (poller + manual) | `LogicProjectFileReader` is stateless; thread-safe | P2 |
| E16 | Plist > 10MB pathological | Cap at 10MB; refuse read → nil | P3 |
| E17 | mtime in the future (clock skew) | Clamp `last_saved_age_sec` to 0 | P3 |
| E18 | Time signature 0/0 | Skip writing `timeSignature`; default | P3 |
| **E19** | **Logic-mid-save atomic write window** (guardian P1) | **mtime-jitter retry: read mtime, parse, re-read mtime; on diff, sleep 50ms + retry once. Persist diff fails → nil → fallthrough.** | P1 |
| **E20** | **AppleScript path contains `..`** (guardian P2) | After `realpath()`, reject if `pathComponents` contains `..`. Validate joined leaf is strict prefix of resolved bundle path. | P1 |
| **E21** | **Project switch mid-resource-read** (boomer P1) | `currentDocumentPath` re-read at the start of each resource call. Cache values that don't match the current path are NOT used (treat as stale). Existing cache invalidation on `hasDocument: false` covers most cases; this is belt-and-braces. Implementation cost ≤ 30 LOC. | P2 |

---

## 6. Security & Permissions

### 6.1 Authentication
N/A.

### 6.2 Authorization
TCC: same surface (Accessibility + Logic Automation). No new entitlements.
POSIX: user-readable file in user's home / project location.

### 6.3 Data Protection (hardened per guardian)

**Path validation flow:**
1. Receive `path` from `AppleScriptChannel.currentDocumentPath()`.
2. `URL(fileURLWithPath: path).resolvingSymlinksInPath()` → `realPath`.
3. Reject if `realPath.pathExtension.lowercased() != "logicx"`.
4. Reject if `realPath.pathComponents.contains("..")`.
5. Verify `realPath` is a directory.
6. Build leaf URL: `realPath.appendingPathComponent("Alternatives/000/MetaData.plist")`.
7. `realpath()` on the leaf.
8. Verify leaf's resolved real path **starts with** `realPath.path + "/"`.
9. Open file via `FileHandle(forReadingFrom:)`. `O_NOFOLLOW` is implicit since `resolvingSymlinksInPath()` already resolved any symlinks in step 2/7.
10. Read at most 10MB; refuse larger.
11. mtime jitter retry per E19.

**Sensitive data**: MetaData.plist contains BPM, time signature, track count, sample rate, key (musical metadata, non-sensitive). Sample paths are NOT surfaced (already true).

**Read-only**: no write paths to project file.

---

## 7. Performance & Monitoring

| Metric | Target | Measurement |
|--------|--------|-------------|
| Plist parse latency | < 50ms p95 (typical 100KB-1MB) | Synthetic benchmark in tests |
| `logic://project/info` end-to-end | < 200ms p95 (warm AS channel) | Existing health timing |
| `logic://tracks` end-to-end | < 300ms p95 | Same |
| File-read failure rate | < 1% per session (excluding "no document") | Log `Log.warn` subsystem `"projectFileReader"` |

### 7.1 Logging
- Subsystem: `"projectFileReader"`
- `info`: read success + mtime
- `warn`: parse failure / path validation failure
- `error`: never (always fallthrough)

---

## 8. Testing Strategy

### 8.1 Unit Tests (target +25 minimum)

- `LogicProjectFileReaderTests` (~10)
  - parses synthetic MetaData.plist (binary + XML)
  - rejects non-`.logicx` paths
  - rejects path with `..` component
  - rejects symlink-escape (leaf real path outside bundle)
  - resolves `/private/Users/...` ↔ `/Users/...`
  - Korean / unicode filename
  - missing keys: nil-out gracefully
  - timesig 0/0 → nil timeSignature
  - mtime future → clamp to 0
  - mtime jitter retry
- `ResourceHandlersTierMergeTests` (~9)
  - **AC-1.4 critical**: cache live tempo 95 + file tempo 80 → response 95, source `"cache"`
  - file tempo 80, cache empty → response 80, source `"project_file"` (+ `last_saved_age_sec`)
  - cache 0 tracks + file 31 → 31 placeholder rows, `placeholder: true` each, source `"ax_live_with_file_count"`
  - cache 31 live tracks → 31 real rows, source `"ax_live"`
  - cache 0 + file unreadable → defaults, source `"default"`
  - **G5 critical**: writing placeholder array does NOT call `cache.updateTracks()` (cache inspect)
  - markers cache populated → returned, source `"ax_live"`
  - markers cache empty + ax_occluded → empty + `ax_occluded: true` envelope
  - envelope `extras` map: `source` always present
- `AXTracksHardeningTests` (~3)
  - synthetic AX tree with Track Headers identifier → tracks returned
  - synthetic AX tree with no Track Headers + only Inspector outline → empty (NOT Inspector labels)
  - synthetic AX tree with track headers via `AXLayoutItem` children path → tracks returned
- `AXMarkersHardeningTests` (~3)
  - synthetic AX tree with marker ruler identified by AXRole+position (no `marker` keyword) → markers returned
  - empty markers → empty
  - no ruler at all → empty
- `BackwardCompatRegressionTests` (~2)
  - decode v3.1.7 envelope (no `source`) into v3.1.8 ProjectInfo → succeeds
  - existing `testProjectInfoResourceIncludesMetadata` keeps passing

### 8.2 Integration Tests
- `Issue7IntegrationTests.swift` (new) — 5 scenarios driven by injected runtime, exercising all tier-merge paths.

### 8.3 Live Verification (manual L1-L3)
1. **L1**: Open `Lofi-Dreamscape-80.logicx`, focus Tracks panel → all 3 resources correct, paste osascript outputs in commit.
2. **L2**: Same project, Mixer panel focused → tracks length ≥ 31 (placeholder OK), project_info still 80/4-4/31, markers reflect cache or empty.
3. **L3**: Close all documents → all 3 resources return defaults / empty without crash.

---

## 9. Rollout Plan

### 9.1 Migration Strategy
Backward-compatible: optional Codable fields with defaults. Existing parsers ignore `source` / `placeholder` / `last_saved_age_sec`.

### 9.2 Feature Flag
None. Strict improvement.

### 9.3 Rollback (revised per guardian)
- `git revert` the commits + `Scripts/release.sh`. Tier ordering preserves v3.1.7 behaviour as inner fallback.
- StateCache is in-memory; restart MCP process after revert to flush.
- **Codable forward-compat**: New fields use Swift `Optional` / default values. A reverted v3.1.7 binary deserialising a v3.1.8-shaped JSON ignores unknown keys (`JSONDecoder` default behaviour for Codable structs). Verified by `BackwardCompatRegressionTests`.

---

## 10. Dependencies & Risks

### 10.1 Dependencies

| Dependency | Risk if Delayed |
|-----------|-----------------|
| `Foundation.PropertyListSerialization` | None |
| Logic Pro AppleScript `path of front document` (12.x verified) | Medium — if 12.3+ removes, fallback to cache; project_info loses Tier 2 |
| `~/Music/Logic` read access | None |

### 10.2 Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| Plist schema drift (Logic version) | Medium | Medium | Defensive optional parsing |
| AX walker hardening introduces 12.x edge regressions | Medium | High | Synthetic AX tree fixtures; multi-signal heuristic |
| Logic 12.3+ adds `markers` term mid-release | Low | Low | Our removed AppleScript path doesn't fight upstream; AX would benefit |
| Live verification skipped (12.0.1 not available) | **Mitigated** — we have it | High | L1-L3 are executable in this session |
| Active variant ≠ 000 | Low | Medium | Documented (OQ-1) |
| **Placeholder leak into cache** (boomer P0) | **Mitigated by G5** — | High | Tier-merge at resource layer; TDD test asserts cache-no-placeholder |

---

## 11. Success Metrics

| Metric | Baseline | Target | Method |
|--------|----------|--------|--------|
| project_info on 12.x with Mixer focused | wrong (defaults) | correct | L2 manual |
| tracks non-empty rate on 12.x with Mixer focused | 0% / Inspector labels | ≥ count placeholders | L2 manual |
| markers `ax_occluded` truthfulness | unknown | matches state | L1 manual |
| Test count delta | 1019 | ≥ 1044 | `swift test --no-parallel` |

---

## 12. Open Questions

- [x] OQ-1: Active-variant detection (`Alternatives/000` vs `001`+)? **Defer.** Document.
- [x] OQ-2: Strip v3.1.5 AppleScript helpers? **Yes — strategist.** Removed (NG4 reversed).
- [x] OQ-3: `source` placement — top-level / extras? **Envelope `extras`.**
- [x] OQ-4: Live verification scope — L1-L3. ✓
- [ ] OQ-5: Marker tri-state revisit trigger? **Decision**: revisit when 3+ user reports of `ax_occluded:true` on real markers, OR Logic 13 ships removing `markers` AX surface.
- [ ] OQ-6: Per-section docPath identity contract revisit trigger? **Decision**: revisit if a user reports cross-project state contamination in v3.1.8+.

---

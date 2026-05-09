<p align="center">
  <img src="https://img.shields.io/badge/Logic_Pro-MCP_Server-000000?style=for-the-badge&logo=apple&logoColor=white" alt="Logic Pro MCP Server" />
</p>

<p align="center">
  <strong>The missing API for Logic Pro.</strong><br/>
  Natural-language control of Logic Pro from Claude and other MCP clients.
</p>

<p align="center">
  <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-6.0+-F05138.svg?style=flat-square" /></a>
  <a href="https://developer.apple.com/macos/"><img src="https://img.shields.io/badge/macOS-14+-000000.svg?style=flat-square&logo=apple" /></a>
  <a href="https://modelcontextprotocol.io"><img src="https://img.shields.io/badge/MCP-0.10-blue.svg?style=flat-square" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square" /></a>
  <img src="https://img.shields.io/badge/tests-1110+_passing-brightgreen.svg?style=flat-square" />
  <img src="https://img.shields.io/badge/version-3.4.4-blue.svg?style=flat-square" />
  <a href="https://github.com/MongLong0214/logic-pro-mcp/stargazers"><img src="https://img.shields.io/github/stars/MongLong0214/logic-pro-mcp?style=flat-square&label=stars" /></a>
</p>

---

If this project helps you make music with Claude, Cursor, or any MCP client, give it a star. It helps this repo reach more Logic Pro users.

Logic Pro has no public API. This server bridges that gap by combining **7 native macOS control channels** into a single MCP interface — giving AI assistants bidirectional, deterministic control over transport, mixing, MIDI composition, plugins, automation, and project lifecycle.

```
You: "Make a 4-bar techno loop in A minor at 140 BPM"

Claude → logic_tracks.record_sequence {
  bar: 1, tempo: 140,
  notes: "45,0,95;57,107,95;45,214,95;..."
}
Claude → logic_tracks.set_instrument {
  index: 0, path: "Electronic Drums/Roland TR-909"
}

Logic Pro: region imported, TR-909 loaded, ready to play.
```

## Why this exists

Logic Pro ships without an AppleScript dictionary rich enough for composition workflows, without OSC, and without a first-party MCP server. Every existing "Logic automation" tool either:

1. Relies on screen-scraping via vanilla AppleScript (slow, fragile, breaks every Logic update)
2. Simulates keyboard shortcuts (no state awareness, no feedback)
3. Uses a single protocol like MCU alone (misses 80% of Logic's surface)

This server takes a different approach: **combine seven complementary channels**, route each operation to the channel best suited for it, and expose a clean MCP tool surface on top.

## What it does

**Mixer** — Control faders, pan, sends, plugin parameters with 14-bit MCU resolution. Bidirectional: state cache reflects what Logic actually did, not what you requested.

**Transport** — Play, stop, record, locate, cycle, tempo, metronome. Sub-millisecond CoreMIDI MMC path; AX dialog fallback for precise bar positioning that auto-extends the project length.

**MIDI composition** — `record_sequence` generates a Standard MIDI File server-side and imports it into a new track. Zero timing drift regardless of system load; notes land at the exact requested bar.

**Library & instruments** — Enumerate Logic's full instrument library (Electronic Drums, Synthesizer, Bass, etc.) and load presets by path. Tree-scan caches to disk for instant subsequent lookups.

**Plugins** — Deterministic plugin parameter control via a Scripter JS insert on the selected track.

**Navigation** — Goto bar, markers by name, zoom, view toggles.

**Project lifecycle** — New, open, save, save-as, close, bounce, quit — all with explicit destructive-operation confirmation.

## Quick Start

**Prerequisites**: macOS 14+, Logic Pro 12.0.1+, Apple Silicon (arm64) native; Intel Macs are supported via Rosetta 2.

### Option A — Homebrew (recommended)

```bash
brew tap MongLong0214/logic-pro-mcp https://github.com/MongLong0214/logic-pro-mcp
brew install logic-pro-mcp
```

The Homebrew formula pins both the release tarball URL and its SHA256; Homebrew itself is a trusted delivery channel with its own signature chain. This is the hardened path for production installs.

### Option B — Download-inspect-run one-line installer

The installer is **fail-closed**: it refuses to run without explicit `LOGIC_PRO_MCP_SHA256` + `LOGIC_PRO_MCP_TEAM_ID` env pins. Inspect the script first, then execute with the pins copied from the release's `SHA256SUMS.txt`:

```bash
curl -fsSL https://raw.githubusercontent.com/MongLong0214/logic-pro-mcp/v3.4.0/Scripts/install.sh -o install.sh
# inspect install.sh, then:
LOGIC_PRO_MCP_SHA256=<paste from release SHA256SUMS.txt> \
LOGIC_PRO_MCP_TEAM_ID=ADHOC \
bash install.sh
```

If you knowingly accept same-origin provenance (hash + Team ID fetched from the same release as the binary), opt in explicitly:

```bash
LOGIC_PRO_MCP_ALLOW_SAME_ORIGIN=1 \
bash <(curl -fsSL https://raw.githubusercontent.com/MongLong0214/logic-pro-mcp/v3.4.0/Scripts/install.sh)
```

See [SECURITY.md §Installer trust model](SECURITY.md#installer-trust-model) for the trust tiers and threat model.

Either path installs the binary, verifies its SHA256, registers with Claude Code, and stages the Key Commands mapping reference (Logic 12.2+ does not auto-import; the reference assists Manual MIDI Learn — see [Setup Guide](docs/SETUP.md) §MIDIKeyCommands). It does **not** configure the MCU control surface or Scripter insert — see the [Setup Guide](docs/SETUP.md) for those two manual steps (~5 minutes).

Then test in Claude:

> "Check Logic Pro MCP health and show all ready channels."

Expected: all 7 channels `ready` (or 5 if you skipped Key Commands and Scripter).

## Architecture at a Glance

```
┌─ MCP Client (Claude / Desktop / Code) ─┐
│                                         │
│   logic_transport   logic_tracks        │
│   logic_mixer       logic_midi          │
│   logic_edit        logic_navigate      │
│   logic_project     logic_system        │
│                                         │
└─────────────────┬───────────────────────┘
                  │ stdio
┌─────────────────▼───────────────────────┐
│  LogicProMCP Server (Swift)             │
│                                         │
│  ┌─ ChannelRouter (130+ operations) ──┐ │
│  │  routes operation → best channel  │ │
│  └───────────────────┬───────────────┘ │
│                      │                  │
│  ┌──────┬──────┬─────▼─────┬──────┐    │
│  │ MCU  │ AX   │ AppleScript│CoreMIDI│ │
│  │      │      │            │        │ │
│  │ CGEvent      Scripter  KeyCmds   │ │
│  └──────┴──────┴───────────┴────────┘ │
│                      │                  │
└──────────────────────┼──────────────────┘
                       │ MIDI / AX / AppleScript
                ┌──────▼───────┐
                │   Logic Pro  │
                └──────────────┘
```

See [Architecture](docs/ARCHITECTURE.md) for deeper details on channel priorities and state flow.

## Documentation

| Document | Audience | Purpose |
|----------|----------|---------|
| [Setup Guide](docs/SETUP.md) | End users | One-page install + Logic Pro integration, ~10 min |
| [API Reference](docs/API.md) | End users, MCP clients | All 8 tools, 9 resources, 3 templates, 130+ operations |
| [Troubleshooting](docs/TROUBLESHOOTING.md) | End users | Common failures and fixes |
| [Architecture](docs/ARCHITECTURE.md) | Contributors | Channel design, state flow, testing strategy |
| [Maintainer Guide](docs/MAINTAINERS.md) | Maintainers | Release, approvals, E2E checklist |
| [Security Policy](SECURITY.md) | Security reviewers | Threat model, reporting, hardening |
| [Changelog](CHANGELOG.md) | Everyone | Per-release changes |
| [Contributing](CONTRIBUTING.md) | Contributors | Dev setup, PR workflow |

## Status

**v3.2.0** (2026-05-07) — Marker provenance. `MarkerState` 가 `position` 의 출처를 `position_source` (`parser` / `fallback` / `unknown`) 로 surface. `goto_marker` 가 fallback/unknown 마커 라우팅 시 응답 extras에 `marker_position_uncertain: true` 추가. **Sub-bar nav 정확도 (NG10) 는 v3.3 로 honest deferred** — T0 live spike 결과 Logic 12.2 dialog가 4-segment AXSlider 구조라 keystroke approach 실패. Codable backward compat — v3.1.x snapshot decode 시 `.unknown`. 자세한 내용 [CHANGELOG §3.2.0](CHANGELOG.md#320--2026-05-07).

**v3.1.11** (2026-05-07) — Issue #9 (`thomas-doesburg`): 영문 Logic 12.2 marker position parser 정확성 + 13 locales 메뉴 경로 + lenient 1-3 components 정책 폐기 (NG11). v3.1.10 → v3.1.11 behavior change: `"17 2"` (2-component lenient) 가 이제 nil — Logic UI는 항상 4 컴포넌트 노출하므로 비-position 셀(tempo 등)이 silently 잘못된 bar로 manufacturing되는 위험 차단. 자세한 내용 [CHANGELOG §3.1.11](CHANGELOG.md#3111--2026-05-07).

**v3.1.10** (2026-05-07) — `goto_marker` routing fix (boomer P1): `transport.goto_position`로 라우팅하여 cache의 정확한 position으로 navigation.

**v3.1.9** (2026-05-07) — Logic Pro 12.2 marker walker fix. Apple removed the `AXRuler` role from the arrange window's AX subtree on 12.2; user markers now live exclusively in the dedicated **Marker List** window's `AXTable`. v3.1.9 ships a 13-locale title-suffix matcher for that window plus a `StateCache.updateMarkers` invariant fix (advance `markersFetchedAt` even on empty-to-empty polls — pre-fix made "honest empty" indistinguishable from "never polled"). Caveat: requires Marker List window to be open; auto-open is opt-in via `LOGIC_PRO_MCP_AUTO_OPEN_MARKER_LIST=1` (planned).

**v3.1.8** (2026-05-06) — Logic Pro 12.x read-path recovery. v3.1.5/3.1.6/3.1.7 all closed Issues #3/#4/#5 via AppleScript-primary reads (`tell front document → tracks/markers/tempo`); 12.x ships a dictionary that does not expose any of those terms. v3.1.8 reads `Alternatives/000/MetaData.plist` for project tempo/timesig/trackCount (per-field merge with cache), hardens the AX walker to refuse Inspector subtree leaks, and removes ~270 LOC of dead AppleScript-primary code. Tier-merge happens at the resource handler (not the channel) so placeholder rows never poison `StateCache`.

**v3.1.1** (2026-04-26) — Honest Contract Extension. v3.1.0 covered 4 ops; v3.1.1 promotes 13 more AX-channel mutating ops (track lifecycle, transport, region, midi.import_file, project.save_as, mixer AC fallback) to the same 3-state envelope, plus unifies `logic://transport/state` under the `{cache_age_sec, fetched_at, data}` envelope. MCU-routed `track.set_automation` and the V-Pot pan State-A enabler are deferred to v3.1.2.

**What changed from v3.0.9**
- `track.set_instrument` now reads back the loaded patch name and reports `verified:true` only when it matches the request; mismatches return `verified:false` with `reason:"readback_mismatch"`.
- `track.select` reads back `AXSelectedChildren` with a 6× retry (100ms each, 600ms budget). A read-back that returns a different index returns `verified:false` with `reason:"readback_mismatch"`; a read-back that never surfaces across the retry budget returns `verified:false` with `reason:"retry_exhausted"`. Neither path silently claims a bare success.
- `mixer.set_volume` / `mixer.set_master_volume` now poll the MCU fader echo into `StateCache` for 500ms (override via `MCU_ECHO_TIMEOUT_MS=250|500|1000`) and return `verified:true` only when a freshly-written echo matches within ±2 LSB (14-bit resolution, tolerance `2/16383`). The freshness stamp prevents an identical-value re-send from being confirmed by a stale cache value left over from the prior call.
- `mixer.set_pan` returns `verified:false` with `reason:"readback_unavailable"` — V-Pot feedback is relative and not yet plumbed through to `StateCache`; the honest answer beats a silent lie.
- `transport.set_cycle_range` (AX path) now returns the `verified` field that the osascript fallback already had.
- `scan_library {mode:"disk"}` no longer poisons the `lastScan` cache that `resolve_path` / `set_instrument` consult; disk-only entries are annotated and do not claim `loadable:true`.
- State resources (`logic://tracks`, `logic://library/inventory`, …) expose `cache_age_sec` + `fetched_at` so clients can detect staleness.

**Compatibility**: mutating-op responses are additive (new `verified` / `reason` / `observed` fields). **Breaking** at the resource layer: `logic://tracks` and `logic://library/inventory` now wrap their payload in `{cache_age_sec, fetched_at, data: …}`, and `logic_tracks.scan_library` wraps its result in `{source, root: …}`. v3.0.9 clients that parsed those payloads directly must read `.data` / `.root` to reach the legacy shape. See CHANGELOG §Compatibility for the full migration diff.

`scan_library` continues to enumerate `~/Music/Logic Pro Library.bundle/Patches/Instrument/` (5,000+ leaves on a full factory install). The v3.0.5 wording that "every patch on disk is addressable via `track.set_instrument`" is withdrawn — paths that the Panel-taxonomy mapper cannot route are now surfaced honestly instead of silently pretending to load.

Notarized (Apple-signed) release requires Apple Developer Program membership ($99/year). Until that's set up, the installer operates in ADHOC mode: SHA256 pin + `codesign --verify` still protect against tampering, but macOS Gatekeeper assessment is skipped and the installer strips the quarantine attribute so the binary runs without warnings.

See [SECURITY.md §Release types](SECURITY.md#release-types) for the trust model detail.

### Testing

- **1110+ unit + integration tests passing** on the v3.4.0 branch (`swift test --no-parallel`). Coverage spans Honest Contract envelopes, fail-closed mutation gates (mixer/marker, track.duplicate State-A verification), routing-audit invariants, AX hardening (track headers, marker list window, marker AX walker locale matrix), `LogicProjectFileReader` plist parsing + path validation (10 MB cap, mtime-jitter retry, `..` rejection), tier-merge at the resource layer, signal-cleanup contract for the stdio supervised-restart path, and audit-phase splitting for L1+ project lifecycle ops.
- **Live E2E** (`Scripts/live-e2e-test.py`): the ~200 environment-independent assertions pass; ~45 tests require a running Logic Pro 12 session with the MCU control surface registered and fail otherwise (documented as environment-gated, not regression)
- Multiple independent production-readiness reviews (code quality, security, architecture) converged to PROCEED after the v3.0.2 hardening passes
- **v3.0.3+ AX-native control surface**: primary GUI touchpoints (track selection, plugin Setting popup) prefer Apple AX actions (AXPress, AXShowMenu, AXSelectedChildren) with CGEvent only as a last-resort fallback — reduces fragility under Logic UI updates
- **v3.0.4 N-column Library navigation**: `track.set_instrument` delegates to the new `LibraryAccessor.selectPath` which clicks every segment in order; the 2-segment legacy caller path still works unchanged.
- **v3.0.5 filesystem-backed `scan_library`**: `LibraryDiskScanner` enumerates the Logic factory bundle on disk (no AX, no Library Panel clicks) and produces a schema-identical `LibraryRoot` with full coverage. Default mode is `disk`; legacy AX scan is available via `{mode:"ax"}`; a diff report is available via `{mode:"both"}`.

### Known limitations

- **`transport.set_tempo`** currently requires the Logic tempo display to be accessible via AX; it returns an error if the control bar layout hides the BPM field. Workaround: set tempo manually in Logic once before calling MCP tempo operations.
- **MIDI File import cosmetics**: `record_sequence` regions start at bar 1 and extend to the target bar (padding CC technique). Note timing inside the region is exact; the leading padding is inaudible. If you need a tight region, trim after import via Logic's **Edit → Trim** menu.

## License

MIT. See [LICENSE](LICENSE).

## Contributing

Bug reports, PRs, and feature discussions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for the dev workflow.

Security vulnerabilities: please do **not** open a public issue. See [SECURITY.md](SECURITY.md) for the private disclosure process.

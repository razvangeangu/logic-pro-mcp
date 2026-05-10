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
curl -fsSL https://raw.githubusercontent.com/MongLong0214/logic-pro-mcp/v3.4.4/Scripts/install.sh -o install.sh
# inspect install.sh, then:
LOGIC_PRO_MCP_SHA256=<paste from release SHA256SUMS.txt> \
LOGIC_PRO_MCP_TEAM_ID=ADHOC \
bash install.sh
```

If you knowingly accept same-origin provenance (hash + Team ID fetched from the same release as the binary), opt in explicitly:

```bash
LOGIC_PRO_MCP_ALLOW_SAME_ORIGIN=1 \
bash <(curl -fsSL https://raw.githubusercontent.com/MongLong0214/logic-pro-mcp/v3.4.4/Scripts/install.sh)
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

**Current release: v3.4.4 (2026-05-09)** — CI green on `macos-15-arm64` GitHub Actions, 1110+ tests passing locally, all P0/P1 items from the 2026-05-08 enterprise production-readiness review closed except `swift-testing` package dependency removal (deferred — Apple has not yet shipped the SwiftPM-side glue that lets the bundled Swift 6 Testing framework resolve `_TestingInternals` without the explicit package dep).

### Active contracts (the things callers most care about)

- **Honest Contract envelope** — every mutating op returns one of three states (`State A` confirmed, `State B` uncertain with `reason`, `State C` hard failure with `error`). Clients can switch on the envelope without parsing free-form text. See [docs/HONEST-CONTRACT.md](docs/HONEST-CONTRACT.md).
- **Fail-closed mutation targets** — mixer faders, plugin params, marker delete/rename, track delete/duplicate require explicit `track`/`index`. Pre-v3.3.0 missing target silently mutated row 0; v3.3.0+ rejects with `requires explicit '<param>'`.
- **Target-faithful navigation** — `goto_marker` returns `element_not_found` (State C) on a cold cache instead of advancing the marker pointer to "next." Caller must `system.refresh_cache` and retry, or supply a `name`.
- **1-based MIDI channel** — `send_note` / `send_cc` / `record_sequence`-`notes`-`ch` accept 1..16 (matches Logic's UI). Pre-v3.1.6 was 0-based.
- **Audit phase split** — `[AUDIT] project.<command> rejected | confirmation_required | executed` distinguishes invalid calls, confirmation prompts, and actual route invocations. Pre-v3.4.0 emitted `executed` before validation.

### Recent releases (one line each)

| Version | Date | Headline |
|---------|------|----------|
| **v3.4.4** | 2026-05-09 | CI hotfix — `MIDIClientCreate(-50)` smoke-test skip on macos-15-arm64 (sandboxed runner has no CoreMIDI server) |
| v3.4.3 | 2026-05-09 | CI Coverage step `find`-based path resolution + diagnostic output |
| v3.4.2 | 2026-05-08 | `ProjectAuditPhaseTests` parallel-execution race fix (`NSLock` + `@Suite(.serialized)`) |
| v3.4.1 | 2026-05-08 | Boomer P2 sweep — fail-loud `lipo` parsing, audit-phase contract docstring, `ci.yml` awk validation, `uninstall-keycmds.sh` empty-backup guard |
| **v3.4.0** | 2026-05-08 | Enterprise deferred-blocker closure (8/9): stdio launch parity (RB-2), release-workflow notarization gate (RB-4), install/uninstall non-TTY safety (RB-6), audit-phase split (H-1, **BREAKING**), `goto_marker` target-faithful (H-2, **BREAKING**), docs drift, CI coverage gate re-armed, AXValue force-cast hardening |
| **v3.3.0** | 2026-05-08 | Enterprise P0 closure: mixer/marker fail-closed (**BREAKING**), `track.duplicate` State-A verified gate (**BREAKING**), signal-cleanup contract (`SIGTERM`/`SIGINT` → coordinated shutdown), `live-e2e-test.py` false-positive expectation removed |
| v3.2.0 | 2026-05-07 | Marker `position_source` provenance surfaced in resource extras; sub-bar nav accuracy honestly deferred to v3.3 (T0 live spike found Logic 12.2 dialog is a 4-segment `AXSlider`) |
| v3.1.11 | 2026-05-07 | Logic 12.2 marker parser strict 4-component, 13-locale menu paths, lenient 1–3 component policy removed (Issue #9) |
| v3.1.6 | 2026-05-04 | `port: "keycmd"` routing for `logic_midi.send_*`, 1-based MIDI channel (**BREAKING**), audited coverage matrix (Issue #1) |
| v3.1.0 | 2026-04-25 | Honest Contract introduced (resource envelope **BREAKING**) |

Per-release detail: [CHANGELOG.md](CHANGELOG.md).

### Distribution

ADHOC release until Apple Developer Program membership lands. SHA256 pin + `codesign --verify` protect against tampering; Gatekeeper assessment is skipped and the installer strips the quarantine attribute. Stable production tags must use the GitHub Actions workflow with notarization secrets; the local `Scripts/release.sh` refuses stable tags without prerelease suffix. See [SECURITY.md §Release types](SECURITY.md#release-types).

### Testing

- **1110+ unit + integration tests** on the v3.4.4 branch — `swift test --no-parallel` PASS. Coverage spans Honest Contract envelopes, fail-closed mutation gates (mixer/marker), routing-audit invariants, AX hardening (track headers, marker list window walker, 13-locale matrix), `LogicProjectFileReader` plist parsing + path validation (10 MB cap, mtime-jitter retry, `..` rejection), tier-merge at the resource layer, `LogicProServer.stop()` signal-cleanup contract, and audit-phase splitting for L1+ project lifecycle ops.
- **Live E2E** (`Scripts/live-e2e-test.py`) defaults to the release binary. Protocol/security/validation assertions run on any host; Logic/CoreMIDI-dependent checks skip unless a live Logic Pro session is detected. Set `LOGIC_PRO_MCP_STRICT_LIVE=1` for attestation runs where a skipped live check must fail.
- **CI coverage gate** — `region ≥ 65%`, `line ≥ 72%` (baseline 70.65 / 77.71%, ~5pp slack). Re-armed in v3.4.0 after the v3.1.5 disable.
- **CoreMIDI smoke tests skip on macos-15-arm64 GitHub runners** (`MIDIClientCreate` returns `-50` in the sandboxed image; production code path coverage on real macOS hosts is unchanged).

### Known limitations

- **`transport.set_tempo`** typed-entry path falls back to slider increment (10-BPM granularity) when Logic's tempo display can't accept text input. Set tempo manually in Logic once before relying on MCP tempo operations for sub-10-BPM precision.
- **`record_sequence`** regions start at bar 1 and extend to the target bar (padding-CC strategy). Note timing inside the region is exact; the leading padding is inaudible but cosmetic. Trim after import via Logic's **Edit → Trim** menu if a tight region matters.
- **`MIDIKeyCommands` channel** — Logic 12.2 doesn't accept the legacy `.plist` Key Commands import (the menu item is grayed out). The bundled `keycmd-preset.plist` is staged as a Manual MIDI Learn reference; eight ops are effectively keycmd-only and require a one-time MIDI Learn binding. See [docs/SETUP.md §4](docs/SETUP.md) for the audited coverage matrix.
- **Marker list resource** (`logic://markers`) returns `[]` honestly when Logic 12.2's Marker List window is closed — Apple removed the `AXRuler` role from the arrange window subtree on 12.2, and user markers now live exclusively in that window's `AXTable`. Auto-open is intentionally not shipped (would change focus without consent); track an opt-in via the issue tracker if you'd like it.

## License

MIT. See [LICENSE](LICENSE).

## Contributing

Bug reports, PRs, and feature discussions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for the dev workflow.

Security vulnerabilities: please do **not** open a public issue. See [SECURITY.md](SECURITY.md) for the private disclosure process.

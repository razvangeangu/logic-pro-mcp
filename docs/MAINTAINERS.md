# Maintainer Guide

Operator and maintainer reference. End users do not need to read this — start with [SETUP.md](SETUP.md) instead.

## Support Matrix

| Area | Supported |
|------|-----------|
| macOS | 14+ (Sonoma, Sequoia) |
| Logic Pro | 12.0.1+ |
| Architectures | GitHub Actions release assets are universal (`arm64` + `x86_64`). Local ADHOC prerelease script output remains `arm64` only and records that fact in `RELEASE-METADATA.json`. |
| MCP clients | Claude Code, Claude Desktop |

## Manual-validation Channels

Two channels (`MIDIKeyCommands`, `Scripter`) cannot be verified programmatically — Logic Pro's preset import and Scripter insertion are not introspectable. They start as `manual_validation_required` and are excluded from routing until explicitly approved.

Approve after manual validation:

```bash
LogicProMCP --approve-channel MIDIKeyCommands --approval-note "Imported preset in Logic Pro"
LogicProMCP --approve-channel Scripter --approval-note "Validated Scripter insertion"
```

List / revoke:

```bash
LogicProMCP --list-approvals
LogicProMCP --revoke-channel MIDIKeyCommands
LogicProMCP --revoke-channel Scripter
```

Revoke whenever the preset is removed, the Scripter instance is removed, or the Logic template is reset.

## Release Process

### ADHOC prerelease (no Apple Developer Program)

```bash
Scripts/release.sh v3.4.6-rc1
```

`Scripts/release.sh` is prerelease-only. It refuses stable tags (`vX.Y.Z`) because a stable ADHOC artifact is indistinguishable from a production release to downstream installers. The installer recognises `team_id: ADHOC` and skips Gatekeeper assessment while keeping SHA256 + codesign verification.

### Notarized release (requires Apple Developer Program, $99/year)

Preconditions — GitHub Actions secrets configured:

- `MACOS_CERT_BASE64` — Developer ID Application certificate, .p12 → base64
- `MACOS_CERT_PASSWORD` — .p12 unlock password
- `MACOS_SIGNING_IDENTITY` — e.g. `Developer ID Application: Your Name (TEAMID)`
- `MACOS_KEYCHAIN_PASSWORD` — random, used for the ephemeral build keychain
- `APPLE_NOTARY_APPLE_ID` — Apple ID email
- `APPLE_NOTARY_TEAM_ID` — 10-character Team ID
- `APPLE_NOTARY_APP_PASSWORD` — app-specific password from appleid.apple.com

Release:

```bash
Scripts/release-stable.sh v3.4.6
```

Do not push stable tags manually. `Scripts/release-stable.sh` verifies the required GitHub Actions secret names, a clean `main` branch matching `origin/main`, absent local/remote tags, absent GitHub Release, and local deterministic gates before it creates and pushes the stable tag. This prevents the stable workflow from being triggered before notarization credentials exist.

`.github/workflows/release.yml` builds a true universal binary, signs/notarizes it, publishes both `LogicProMCP-macOS-universal.tar.gz` and the backward-compatible `LogicProMCP-macOS-arm64.tar.gz` alias, and records the actual architecture list in `RELEASE-METADATA.json`. The downstream install validation job runs on both Apple Silicon and Intel runners so the release asset path is exercised on each architecture. If a stable tag is pushed without the required secrets, the workflow fails closed before artifact publication; rerun it only after the secrets are configured.

### Post-tag steps (both release modes)

After the GitHub release is published, the Homebrew formula still points at the **old** tarball SHA256. Update it:

```bash
VERSION=v3.0.2
curl -fsSL "https://github.com/MongLong0214/logic-pro-mcp/releases/download/$VERSION/SHA256SUMS.txt" \
    | awk '$2 == "LogicProMCP-macOS-universal.tar.gz" {print $1}'
# copy the hex into Formula/logic-pro-mcp.rb `sha256 "…"`
```

Commit the formula update as a separate follow-up (it is not on the tag). Users installing via `brew install` against the tap will then resolve to the newly-published artifact.

If you also maintain a private Homebrew tap, publish the formula update there.

### Environment variables (runtime)

| Variable | Scope | Purpose |
|----------|-------|---------|
| `LOG_LEVEL` | Server | `debug`/`info`/`warn`/`error`. Default `info`. |
| `LOG_FORMAT` | Server | `json` for one-line structured logs (machine-parseable), otherwise plain text (default). |
| `LOGIC_PRO_MCP_LIBRARY_INVENTORY` | Server | Absolute path to a pre-scanned `library-inventory.json`. Overrides the `<CWD>/Resources/…` and `~/Library/Application Support/LogicProMCP/…` lookup order. Symlinks are resolved and validated (must be a regular `.json` file ≤ 64 MiB) before reading. **Path must sit under one of the allowlist roots** (`~/Library/Application Support/LogicProMCP/`, `<CWD>/Resources/`, `~/Music/Logic/`); arbitrary user-readable JSON files (e.g. Keychain exports, third-party config) are rejected even if the suffix matches. Extend via `LOGIC_PRO_MCP_INVENTORY_ALLOWLIST`. |
| `LOGIC_PRO_MCP_INVENTORY_ALLOWLIST` | Server | **Additive** colon-separated extension to the inventory path allowlist (`PATH`-style). Use when the inventory legitimately lives outside the default roots — e.g. a shared team mount at `/Volumes/Music/inventory/`. Paths are symlink-resolved and prefix-matched; the safe defaults always remain. |
| `LOGIC_PRO_MCP_SHA256` | Installer | Pin the expected binary SHA256 out-of-band (do not rely on same-origin `SHA256SUMS.txt`). |
| `LOGIC_PRO_MCP_TEAM_ID` | Installer | Pin the expected codesign Team Identifier (e.g. `ADHOC` or a 10-char Apple Team ID). |
| `LOGIC_PRO_MCP_VERSION` | Installer | Override the pinned release tag (default is the installer's baked-in version). |

## E2E Validation Checklist

After any release, exercise these against live Logic Pro 12:

1. `logic_system.health` — all 7 channels `ready`
2. `logic_transport.play` / `.stop`
3. `logic_tracks.select` / `.record_sequence` → verify region at expected bar
4. `logic_mixer.set_volume` / `.set_pan` / `.set_plugin_param`
5. `logic_edit.undo` / `.redo`
6. `logic_project.open` (with `confirmed: true`)
7. `logic_navigate.goto_bar` / `.goto_marker` by name
8. `logic_system.health` — recheck after operations
9. `logic_project.save_as` (with `confirmed: true`) — require HC `verified:true`, `observed`, and `observed_mtime`
10. `logic_midi.import_file` — import a staged `/tmp/LogicProMCP/*.mid` and require a new live AX track before the next import
11. `logic://project/info` — confirm live transport tempo/sample-rate provenance and saved metadata fallback behave as documented

Evidence to capture for a release:

- Screen recording of Logic Pro showing expected region placement
- `LogicProMCP --check-permissions` output
- `LogicProMCP --list-approvals` output
- `logic_system.health` JSON payload
- `swift test` and `swift build -c release` output
- For composition artifacts, a `ProjectData` or package-level check proving expected MIDI regions exist and no unintended audio files were packaged

## Destructive Operation Policy

Operations that can lose work (`quit`, `close`, `open`, `save_as`, `bounce`) require `{ "confirmed": true }` in the MCP call. Without the flag they return a structured `confirmation_required` response. See `Sources/LogicProMCP/Utilities/DestructivePolicy.swift`.

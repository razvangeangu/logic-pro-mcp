# Issue #49 Verification — MIDI Import Path Normalization

Date: 2026-06-19 KST
Issue: `#49 Demo QA: MIDI import rejects valid /tmp LogicProMCP paths after macOS path normalization`
Branch: `fix/demo-qa-49-import-path`

## Root Cause

`MIDIDispatcher.importFilePathParam` validated the caller path against a single managed prefix after path normalization. The check accepted only `/tmp/LogicProMCP/*.mid`, so callers using the macOS alias `/private/tmp/LogicProMCP/*.mid` were rejected before the AX import path ran.

The AX channel had the same boundary assumption: it only treated the `/tmp/LogicProMCP/` spelling as managed, even though the same file can legitimately appear through the `/private/tmp` alias on macOS.

## Fix

1. Added a shared managed-temp prefix helper in `AccessibilityChannel` so both dispatcher and AX validation use the same allowlist.
2. Accepted both `/tmp/LogicProMCP/` and `/private/tmp/LogicProMCP/` plus their normalized aliases.
3. Kept the fail-closed checks for control characters, extension, regular-file status, and symlink/traversal escapes.

## Deterministic Verification

Targeted regression tests run on the branch:

- `swift test --filter testMIDIDispatcherRoutesImportFileCommand`
- `swift test --filter testMIDIDispatcherRoutesPrivateTmpImportFileCommand`
- `swift test --filter testAccessibilityChannelValidatedMIDIImportPathAcceptsManagedTempMID`
- `swift test --filter testAccessibilityChannelValidatedMIDIImportPathAcceptsPrivateTmpRepresentation`

Observed result:

- All 4 targeted tests passed.

## Live E2E Verification

Environment:

- Logic Pro 12.2
- Strict live MCP transport via `tmux`
- Release binary: `.build/release/LogicProMCP`

Notes:

- An initial probe from the `Choose a Project` bootstrap state produced `readback_mismatch` for the first `/tmp` import because no real project window had been established yet. That is bootstrap-state noise tracked separately under `#45`, not a path-validation failure.
- After Logic entered a normal arrange-window project (`Untitled 3 - Tracks`, `track_count: 1`), both path spellings succeeded.

Targeted live probe result:

```text
health: {"project": "Untitled 3 - Tracks", "track_count": 1}
tmp /tmp/LogicProMCP/issue49-live-tmp-2.mid
{"observed_delta":1,"requested":"\/tmp\/LogicProMCP\/issue49-live-tmp-2.mid","success":true,"track_count_after":2,"track_count_before":1,"verified":true,"via":"ax_menu_import"}
private /private/tmp/LogicProMCP/issue49-live-private-2.mid
{"observed_delta":1,"requested":"\/tmp\/LogicProMCP\/issue49-live-private-2.mid","success":true,"track_count_after":3,"track_count_before":2,"verified":true,"via":"ax_menu_import"}
```

Conclusion:

- `/tmp/LogicProMCP/*.mid` succeeds in a real Logic session.
- `/private/tmp/LogicProMCP/*.mid` also succeeds and is normalized onto the same managed import path.
- The path bug from `#49` is fixed; remaining import failures from bootstrap/modal/project state belong to other issues, not path normalization.

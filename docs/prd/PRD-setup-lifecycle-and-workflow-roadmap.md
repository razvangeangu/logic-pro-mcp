# PRD: Setup Lifecycle, Batch Export, and Session Audit Roadmap

**Status**: Draft
**Date**: 2026-06-17
**Owner**: Logic Pro MCP
**Related issues**:

- https://github.com/MongLong0214/logic-pro-mcp/issues/26
- https://github.com/MongLong0214/logic-pro-mcp/issues/27
- https://github.com/MongLong0214/logic-pro-mcp/issues/28

**Primary priority**: install / update / uninstall / doctor lifecycle
**Follow-up priorities**: batch bounce/stem/export workflow; project/session audit + cleanup plan

## 1. Problem

Recent external feedback confirms that the strongest product value is not "AI writes music for you." It is a trusted local DAW operator for boring, risky, repeatable Logic Pro work. The same feedback also exposes the current adoption bottleneck: users can understand the concept, but installation, setup validation, recovery, and removal still feel too manual.

The current project already has useful pieces:

- `Scripts/install.sh` installs a pinned release binary and verifies SHA256/signature/Gatekeeper.
- `Scripts/uninstall.sh` removes the binary, manual approval store, Claude Code registration, and key-command staging.
- `LogicProMCP --check-permissions` checks Accessibility and Automation.
- `logic_system health` and `logic://system/health` expose runtime channel health.
- `docs/SETUP.md` and `docs/TROUBLESHOOTING.md` document setup and failure recovery.

These pieces are not yet a coherent lifecycle product. A user should be able to answer:

- Is Logic Pro MCP installed correctly?
- What version/source is installed?
- Is it registered with my MCP client?
- Are macOS permissions, Logic Pro, MCU, Scripter, Key Commands, and PATH ready?
- Can I update safely?
- Can I uninstall without leaving hidden MCP artifacts behind?
- If something is broken, what exact next command or manual Logic Pro step fixes it?

## 2. Goals

### Priority 1: setup lifecycle doctor

- Provide one user-facing lifecycle surface for install, update, uninstall, and doctor checks.
- Make `doctor` idempotent, non-mutating, and useful before and after installation.
- Emit both human-readable output and machine-readable JSON.
- Detect install source: Homebrew, pinned release binary, or source build.
- Detect MCP client registration status for Claude Code first, with extension points for Claude Desktop and generic MCP config.
- Detect macOS permission state without triggering unexpected write actions.
- Detect Logic-side readiness: Logic Pro running, MCU virtual port availability, MCU registration/feedback, Scripter approval, Key Commands approval, and stale/manual-validation states.
- Keep the existing fail-closed installer trust model: no mutable `latest` release install outside explicit safe paths.
- Add dry-run support to every lifecycle mutation path.

### Priority 2: batch bounce/stem/export workflow

- Add a production-safe workflow for folder/project-level export jobs such as "open each project, create a bass-muted bounce, place exports in a handoff folder, and produce a manifest."
- Start with local file output only. No automatic email, Dropbox upload, or external publishing in the first production scope.
- Require explicit confirmation for every project-open, save, bounce, and close boundary.
- Verify exported file existence, modification time, expected naming, and per-project manifest entries.

### Priority 3: project/session audit + cleanup plan

- Produce a read-first project/session audit that surfaces tracks, regions, mixer state, routing, muted/unused material, naming/color irregularities, clipping/routing suspicion, and plugin-slot provenance.
- Generate a cleanup plan before making changes.
- Keep cleanup mutation as a separate guarded step: explicit targets, per-operation confirmation, readback after each write, and fail-closed on stale or incomplete inventory.

## 3. Non-Goals

- No cloud account setup, Dropbox upload, email sending, or external publishing in the first implementation.
- No automatic destructive cleanup without a reviewed plan and explicit confirmation.
- No hidden macOS permission prompts during `doctor`.
- No "latest" shell install that bypasses the existing provenance policy.
- No attempt to programmatically remove manual Logic Pro objects that Apple does not expose safely, such as a Scripter insert or Control Surface card. The tool may detect and guide; it must not pretend complete removal if manual steps remain.
- No AI composition or co-writer scope.

## 4. Product Surface

### 4.1 Lifecycle commands

Preferred public UX:

```bash
LogicProMCP doctor
LogicProMCP doctor --json
LogicProMCP doctor --online
LogicProMCP install --dry-run
LogicProMCP update --dry-run
LogicProMCP uninstall --dry-run
```

Because `install` must work before the binary exists, the release bootstrap script remains necessary:

```bash
curl -fsSL https://raw.githubusercontent.com/MongLong0214/logic-pro-mcp/<tag>/Scripts/install.sh -o install.sh
LOGIC_PRO_MCP_SHA256=<sha> LOGIC_PRO_MCP_TEAM_ID=<team_id> bash install.sh
```

The implementation should converge both paths around one shared lifecycle engine:

- shell bootstrap: downloads/verifies/copies the binary, then delegates post-install validation to `LogicProMCP doctor`
- installed binary: runs local doctor checks and can orchestrate safe update/uninstall flows
- Homebrew: remains the recommended install/update path; doctor detects and reports it

### 4.2 Doctor output model

`doctor --json` returns a stable schema:

```json
{
  "schema": "logic_pro_mcp_doctor.v1",
  "overall": "ok|warn|fail|manual",
  "version": {
    "installed": "v3.7.0",
    "source": "homebrew|release|source|unknown",
    "path": "/usr/local/bin/LogicProMCP",
    "release_metadata": "ok|missing|mismatch|not_checked"
  },
  "checks": [
    {
      "id": "macos.accessibility",
      "status": "ok|warn|fail|manual|not_checked",
      "summary": "Accessibility is granted",
      "evidence": { "trusted": true },
      "fix": {
        "kind": "manual|command|docs",
        "text": "System Settings > Privacy & Security > Accessibility",
        "command": null,
        "url": "docs/SETUP.md#2-grant-macos-permissions"
      }
    }
  ]
}
```

Status semantics:

- `ok`: ready and verified.
- `warn`: usable with a known limitation.
- `fail`: blocks a supported workflow and has a concrete fix.
- `manual`: requires user action that cannot be safely automated.
- `not_checked`: intentionally skipped, usually because `--online` or Logic Pro is not running.

### 4.3 Required doctor checks

| Check ID | Required evidence | Failure action |
|----------|-------------------|----------------|
| `install.path` | binary exists, executable bit, PATH location | show install command or PATH fix |
| `install.source` | Homebrew cellar/formula, release metadata, or source build marker | report unknown source, do not update automatically |
| `install.version` | binary version and release tag when available | show update command |
| `install.signature` | codesign verify, Team ID / ADHOC policy | fail if mismatched |
| `install.quarantine` | `com.apple.quarantine` xattr absent/present | show safe removal only for verified ADHOC release |
| `mcp.claude_code` | `claude mcp list` / config contains `logic-pro` | show exact `claude mcp add` or remove/fix command |
| `macos.accessibility` | `AXIsProcessTrustedWithOptions(prompt:false)` | manual System Settings fix |
| `macos.automation_logic` | no-prompt verifiable Automation state when Logic is running | manual System Settings fix |
| `logic.running` | `ProcessUtils.isLogicProRunning` | warn if stopped; fail only for live channel checks |
| `midi.ports` | virtual CoreMIDI/MCU/KeyCmd ports published | restart MCP or show setup hint |
| `logic.mcu` | channel health, feedback freshness, registration hint | point to `docs/SETUP.md#3-register-mcu-control-surface` |
| `logic.key_commands` | manual validation store + channel health detail | manual MIDI Learn guidance |
| `logic.scripter` | manual validation store + channel health detail | Scripter insert guidance |
| `runtime.resources` | `logic://system/health` schema readable when server is launched as MCP | show MCP transport/log diagnosis |
| `docs.links` | all remediation anchors exist in docs | fail tests if stale |

### 4.4 Install/update/uninstall behavior

Install:

- default to Homebrew in docs and UI hints.
- keep the pinned shell installer for users who cannot use Homebrew.
- reject mutable `latest` unless explicitly using Homebrew or a documented maintainer-only path.
- run doctor after install and print the next incomplete manual step.

Update:

- detect install source first.
- Homebrew source: print and optionally run `brew update && brew upgrade logic-pro-mcp`.
- release binary source: require pinned target version and provenance pins, then replace atomically.
- source build: do not auto-update; print `git pull && swift build -c release` guidance.
- always support `--dry-run`.
- never downgrade unless `--allow-downgrade` is explicit.

Uninstall:

- remove Claude Code MCP registration when present.
- remove binary, approval store, staged key-command reference, and known helper assets.
- report manual leftovers: Logic Control Surface card and Scripter insert.
- support `--dry-run`.
- be idempotent: missing artifacts are skipped, not treated as errors.
- do not delete user projects, Logic preferences, sound libraries, or unrelated MCP configs.

## 5. Implementation Plan

### T1: Doctor model and local checks

- Add a `DoctorCheck` model and JSON encoder.
- Add `LogicProMCP doctor` / `--doctor` entrypoint compatibility.
- Cover permission, PATH, version, codesign, quarantine, install-source, and MCP registration checks.
- Unit-test schema stability and status aggregation.

### T2: Runtime Logic checks

- Reuse existing `PermissionChecker`, `ProcessUtils`, `ManualValidationStore`, channel health, and `logic://system/health` code.
- Add checks for MCU, Key Commands, Scripter, and resource readability.
- Avoid triggering mutating operations.
- Unit-test Logic-not-running and permission-denied branches.

### T3: Lifecycle orchestration

- Refactor `Scripts/install.sh` / `Scripts/uninstall.sh` around dry-run-safe reusable helpers.
- Add `update` behavior by install source.
- Add post-install doctor call.
- Add idempotent uninstall verification.

### T4: Documentation and remediation links

- Rewrite setup docs around the lifecycle surface.
- Keep manual Logic Pro setup steps explicit.
- Add `TROUBLESHOOTING.md` entries for every doctor check ID.
- Add a docs-link test so doctor remediation anchors cannot drift.

### T5: E2E and release validation

- Deterministic tests: full Swift suite, script contract tests, JSON schema tests.
- Release checks: macOS 14/15 install validation still passes.
- Live smoke: `doctor --json` before Logic, with Logic running but incomplete setup, and with full setup.
- Uninstall smoke in a temporary install directory.

## 6. Acceptance Criteria

- `LogicProMCP doctor --json` returns `schema:"logic_pro_mcp_doctor.v1"` and machine-parseable check entries.
- `doctor` never mutates Logic Pro, MCP client config, filesystem install state, or permissions.
- Every `fail` or `manual` check includes a specific remediation command, docs link, or manual UI path.
- Doctor check IDs are stable and documented.
- `install.sh` remains fail-closed on missing provenance pins unless `LOGIC_PRO_MCP_ALLOW_SAME_ORIGIN=1` is explicit.
- `update --dry-run` reports the planned source-specific update path without changing files.
- `uninstall --dry-run` reports all artifacts it would remove.
- Real uninstall is idempotent and does not remove user projects, Logic preferences, or sound libraries.
- Existing `--check-permissions`, `--approve-channel`, `--revoke-channel`, and `--list-approvals` remain backward-compatible.
- `docs/SETUP.md` can be followed by a new user without reading source code.
- Tests include Swift unit tests, script contract tests, docs-anchor tests, release build, `python3 -m py_compile Scripts/live-e2e-test.py`, and a scoped install/uninstall smoke test.

## 7. Follow-up Priority: Batch Bounce/Stem/Export Workflow

Problem: users want the agent to perform repetitive project handoff work, not just single-project control. A representative workflow is: open projects in a folder, produce a variant bounce with one part muted, place output files in a handoff directory, and create a manifest.

Initial scope:

- local-only batch export plan and execution surface.
- explicit project list; no recursive guessing by default.
- output directory allowlist and collision policy.
- per-project open/save/bounce/close confirmation.
- manifest with source project, requested variant, output path, created time, observed file size, and verification status.
- fail-closed if Logic opens the wrong project, bounce output is missing, or project close/save state is ambiguous.

Non-goals:

- no automatic email, Dropbox upload, cloud sharing, or external publishing.
- no destructive source project edits.
- no silent overwrite of existing exports.

Acceptance:

- dry-run plan lists every project and output artifact before opening Logic.
- live E2E verifies at least one scoped project export.
- batch run can resume or skip already verified outputs from the manifest.
- every output is locally verified by existence, mtime, and non-zero size.

## 8. Follow-up Priority: Project/Session Audit + Cleanup Plan

Problem: users want help understanding messy projects before committing changes. The product should first become excellent at reading and explaining the session, then propose cleanup, then apply only confirmed small changes.

Initial scope:

- read-only audit resource/workflow using project info, tracks, regions, markers, mixer, plugin inventory, routing hints, and cache provenance.
- deterministic findings: empty tracks, long-muted tracks, suspicious solo/mute states, unnamed tracks, missing regions, stale mixer readback, occupied plugin slots, possible routing gaps, and export-readiness blockers.
- cleanup plan object with target IDs, proposed operation, risk level, required confirmation, expected readback, and rollback note.
- guarded execution only after plan review.

Non-goals:

- no AI-only invisible rewrite of project structure.
- no deletion by default.
- no claims about audio quality, mix correctness, or musical intent unless supported by explicit measurable state.

Acceptance:

- read-only audit works without mutating Logic.
- cleanup plan is serializable and can be shown to an MCP client before execution.
- each mutating cleanup step uses existing Honest Contract State A/B/C semantics.
- a failed or stale readback stops the remaining cleanup sequence.

## 9. Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Doctor becomes another noisy checklist | users ignore it | stable severity model, exact fix per check, compact default output |
| Installer weakens provenance policy | supply-chain risk | preserve current fail-closed pins and test it |
| Uninstall overreaches | data loss or broken Logic setup | never touch projects, preferences, sound libraries; dry-run required in docs |
| Logic manual setup cannot be automated | user confusion | mark `manual` honestly and link exact UI steps |
| Batch export touches wrong project | serious trust failure | explicit project path list, active project readback, per-project manifest |
| Cleanup plan deletes useful material | trust failure | read-only plan first, no default delete, per-step confirmation |

## 10. Verification Gates

- `swift test --no-parallel`
- `swift build -c release`
- `python3 -m py_compile Scripts/live-e2e-test.py`
- `git diff --check`
- script contract tests for install/update/uninstall dry-run
- doctor JSON schema tests
- docs remediation anchor tests
- macOS install validation job
- scoped live Logic Pro doctor smoke
- scoped live Logic Pro batch export smoke only after the export issue reaches implementation

## 11. ADR

**Decision**: prioritize setup lifecycle doctor before new music workflows.

**Drivers**:

- External feedback shows installation/setup friction is an adoption blocker.
- A reliable doctor improves every future support path.
- Batch export and session audit need the same trust model: explicit state, provenance, and fail-closed verification.

**Alternatives considered**:

- Add more creative Logic tools first.
- Build batch export immediately.
- Keep setup as docs-only.

**Why chosen**:

Creative tooling does not solve the main trust/adoption problem. Batch export is valuable, but it depends on reliable install, update, permissions, Logic readiness, and diagnostics. Docs-only setup has already reached its limit; users need a command that can inspect their machine and say exactly what is wrong.

**Consequences**:

- The next implementation should improve activation and support more than demo breadth.
- Some setup steps remain manual, but the product will label them honestly.
- Future workflows can rely on doctor output as a preflight gate.

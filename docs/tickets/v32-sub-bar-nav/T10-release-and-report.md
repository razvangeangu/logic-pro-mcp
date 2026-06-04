# T10 — Release v3.2.0 + Final Report

> Historical record (2026-06-05 docs refresh): latest production-readiness and live E2E evidence is in `README.md`, `CHANGELOG.md`, and `docs/live-verify-v3.4.5-rc5.md`; this file remains preserved implementation context.

**Status**: Todo
**Depends on**: T1-T9 all complete + Phase G final review ALL PASS
**Size**: S
**PRD**: §10 success metrics

## Procedure

1. Confirm `git status` clean
2. `swift test --no-parallel` → 1074+ PASS
3. `swift build -c release` → 0 warnings
4. **Phase G final 4-agent review (boomer + strategist + guardian + tester)** ALL PASS
5. `bash Scripts/release.sh v3.2.0`
6. SHA 3-way integrity verification:
   - Formula sha256
   - GH release SHA256SUMS.txt
   - Downloaded tarball actual SHA
   - All match ✓
7. `brew uninstall logic-pro-mcp` → `brew untap` → `brew tap` (force fresh) → `brew install` → `brew test` PASS
8. `LogicProMCP --check-permissions` → granted
9. **User (Isaac) live verification** Tier 2 (T9 runbook) — English 12.2, Korean 12.2, IME ON 3 scenarios
10. User report — 8-phase summary, 11 principles mapping, success metrics

## User Report Form (reference)

```markdown
# v3.2.0 Completion Report — NG10 closed + Boomer P2-3 closed

**Release**: https://github.com/MongLong0214/logic-pro-mcp/releases/tag/v3.2.0

## 8 Phase Results
| Phase | Result |
|-------|--------|
| A — Code analysis | ✅ |
| B — PRD v0.1~v0.4 | ✅ Boomer 4-round → ALL PASS |
| C — PRD review | ✅ Boomer ALL PASS |
| D — Ticket decomposition (T0-T10) | ✅ |
| E — Ticket review | ✅ |
| F — TDD implementation (after T0 PASS, T1-T9) | ✅ 1074+ PASS |
| G — Final review | ✅ ALL PASS |
| H — Release + brew test + Tier 2 live | ✅ |

## 11 Principles Mapping
[Korean comments + AC-4.x grep results for each T1-T9 ticket]

## Integrity Verification
- Formula sha256 = SHA256SUMS = downloaded tarball
- brew install + test PASS

## Change Summary
- NG10 closed (sub-bar nav accuracy)
- Boomer P2-3 closed (marker provenance)
- 28+ test cases added
- Codable backward compat guaranteed

## Follow-up (v3.3)
- Logic 11.x AX surface verification
- Timecode precision nav (mmc.locate auto-routing)
```

## Acceptance Criteria

- **AC-T10.1**: SHA 3-way match
- **AC-T10.2**: brew install + test PASS
- **AC-T10.3**: Tier 2 live verification PASS (Isaac directly)
- **AC-T10.4**: GitHub release page has RELEASE-METADATA.json + SHA256SUMS.txt + tarball + binary all attached
- **AC-T10.5**: User report written + Issue #9 (already closed) update comment (NG10 closed in v3.2.0 + link)
- **AC-T10.6**: Memory updated — `project_v320_shipped.md` + MEMORY.md index

## Out of Scope

- v3.3 PRD start — separate cycle

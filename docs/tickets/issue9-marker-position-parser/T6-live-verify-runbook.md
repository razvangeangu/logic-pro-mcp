# T6: live-verify-v3.1.11.md (3-tier runbook)

> Historical record (2026-06-09 docs refresh): latest production-readiness and live E2E evidence is in `README.md`, `CHANGELOG.md`, and `docs/live-verify-v3.4.6.md`; this file remains preserved implementation context.

**PRD Ref**: PRD-issue9 > §8.3
**Priority**: P2
**Size**: S (< 30min)
**Status**: Todo
**Depends On**: T1-T5

---

## 1. Objective
Permanent verification procedure — future maintainers responding to v3.2 or new Logic versions can reproduce the same verification matrix.

## 2. Acceptance Criteria
- [ ] AC-1: `docs/live-verify-v3.1.11.md` created — Tier 1 (auto), Tier 2 (live), Tier 3 (NG / honest disclosure).
- [ ] AC-2: Live e2e procedure specifies the per-app language switch safety procedure (System Settings path) — system-wide `defaults write` prohibited.
- [ ] AC-3: Non-bar-aligned marker creation procedure + verification command + expected response.
- [ ] AC-4: NG10 sub-bar navigation limitation documented — guide users to wait for v3.2.

## 3. Implementation

### 3.1 Files
| File | Change |
|------|--------|
| `docs/live-verify-v3.1.11.md` | Create new |

### 3.2 Outline

```markdown
# Live Verification — v3.1.11 (Issue #9)

## Tier 1: Automated
- swift test --no-parallel → 1075 PASS
- swift build -c release → 0 warnings
- brew test logic-pro-mcp → exit 0
- testServerVersionMatchesPackagingArtefacts → PASS

## Tier 2: Live (Logic Pro 12.2)
### 2.1 Trailing-dot position (English 12.2)
- Language switch (per-app, safe): System Settings → Language & Region → Apps → Logic Pro → English
- Logic restart
- New project + 1 non-bar-aligned marker (Navigate → Create Marker, playhead at bar 5 beat 2 div 3 tick 100)
- Verify `logic://markers` response: position == `"5.2.3.100"`
- Quit Logic → System Settings → Logic Pro → Korean restore

### 2.2 Lenient retirement regression
- Even if (hypothetically) a header row abbreviated form appears in the same project, verify the fallback is applied rather than silently navigating to a wrong bar

### 2.3 13 locale menu path
- Confirm `Navigate → Open Marker List` works in English build (confirm absence from Window menu)

## Tier 3: NG / Honest Disclosure
- NG10 sub-bar navigation: cache is accurate but navigate is bar-level (v3.2 PRD planned)
- NG11 lenient retired: behavior change honestly documented
- NG5 (legacy) → retired — 13 locales all doc-covered
```

## 4. Review Checklist
- [x] Safe language switch procedure
- [x] NG documented
- [x] Reproducible for future Logic versions

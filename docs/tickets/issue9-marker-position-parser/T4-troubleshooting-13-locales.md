# T4: TROUBLESHOOTING — 13 locales + missing Window menu entry

> Historical record (2026-06-05 docs refresh): latest production-readiness and live E2E evidence is in `README.md`, `CHANGELOG.md`, and `docs/live-verify-v3.4.5-rc5.md`; this file remains preserved implementation context.

**PRD Ref**: PRD-issue9 > AC-3.1 (Boomer P1-2)
**Priority**: P1
**Size**: S (< 30min)
**Status**: Todo
**Depends On**: None (can run in parallel)

---

## 1. Objective
Document in `docs/TROUBLESHOOTING.md` the discoverability gap that the English 12.2 reporter encountered while searching the Window menu, so users across all locales do not hit the same issue again.

## 2. Acceptance Criteria
- [ ] AC-1: The "Fix:" section under `logic://markers always returns empty` in TROUBLESHOOTING.md includes:
  - **All builds**: The Marker List window is under the **Navigate** menu (not the Window menu).
  - All 13 locales use the same menu location (only the label name changes per locale).
  - No marker entry in the Window menu — confirmed by English reporter.
- [ ] AC-2: v3.1.9 / v3.1.10 status entries in README remain unchanged. v3.1.11 entry added in T5.
- [ ] AC-3: Written in English.

## 3. Implementation

### 3.1 Files to Modify
| File | Change |
|------|--------|
| `docs/TROUBLESHOOTING.md` | Expand "Fix" section under `logic://markers` |

### 3.2 Diff sketch

Before:
```markdown
**Fix:** open the Marker List window once via `탐색 → 마커 목록 열기` (KR) / `Navigate → Open Marker List` (EN). After ~3-15 seconds the next poll cycle picks up the markers.
```

After:
```markdown
**Fix**: The Marker List window is under the **Navigate** menu (not the Window menu — confirmed by `thomas-doesburg` in Issue #9 for English 12.2).

| UI Locale | Menu path |
|-----------|-----------|
| Korean | `탐색 → 마커 목록 열기` (`Navigate → Open Marker List`) |
| English | `Navigate → Open Marker List` |
| Japanese / French / German / Spanish / Italian / Chinese (Simplified/Traditional) / Russian / Portuguese / Dutch | Same menu location — look for the Navigate equivalent in your locale |

The code recognizes Marker List window titles for 13 locales (`AXLogicProElements.markerListWindowSuffixes`). If the menu label is unclear in your locale, you can temporarily switch Logic Pro's language to English in System Settings → Language & Region → Apps → Logic Pro, then switch back after confirming.

Open the window once and after ~3-15 seconds the next poll cycle will surface the markers from cache.
```

## 4. Review Checklist
- [x] Boomer P1-2 — 13 locales integrated
- [x] Missing Window menu entry documented
- [x] Per-app language switch recommended (system-wide `defaults write` avoided)

# Live Verification Runbook — v3.1.11 (Issue #9)

> Historical record (2026-06-12 docs refresh): latest production-readiness and live E2E evidence is in `README.md`, `CHANGELOG.md`, and `docs/live-verify-v3.5.0.md`; this file remains preserved implementation context.

**Verification timing**: Immediately before v3.1.11 release + for reproducing on user reports.
**Target fix**: `parseMarkerListPosition` strict 4 + trailing punctuation strip + 1-based + ASCII narrow + mixed separator reject.
**Target doc**: TROUBLESHOOTING.md 13-locale menu paths.

---

## Tier 1 — Automated (CI / dev box)

```bash
swift test --no-parallel
# → 1064 / 1064 PASS

swift build -c release
# → 0 warnings

swift test --no-parallel --filter parseMarkerListPosition
# → 2 functions (parameterized 25 cases) ALL PASS

swift test --no-parallel --filter testServerVersionMatchesPackagingArtefacts
# → version 3.1.11 all artifacts synchronized and verified

brew test logic-pro-mcp  # after install
# → exit 0
```

Additional verification (user 11-principle measurable items):

```bash
# AC-4.2: 0 new TODO/FIXME/XXX entries
git diff main..HEAD -- Sources/ | grep -E '^\+.*\b(TODO|FIXME|XXX)\b'
# → 0 lines (expected)

# AC-4.6: parser body ≤ 20 lines
awk '/static func parseMarkerListPosition/,/^    \}$/' \
  Sources/LogicProMCP/Accessibility/AXLogicProElements.swift | wc -l
# → 15 lines (signature + body + closing brace)
```

---

## Tier 2 — Live (Logic Pro 12.2 real device)

### 2.1 English 12.2 non-bar-aligned marker regression (F2 fix verification)

**Language switch (per-app, safe)**:
1. System Settings → Language & Region → Apps → Logic Pro → select English
2. Quit Logic Pro + relaunch

**Scenario**:
1. Create a new project (BPM 120, 4/4)
2. `Navigate → Open Marker List` (not the Window menu — confirmed in English 12.2)
3. Add 1 marker and move it to a non-bar-aligned position (e.g., bar 5 beat 2 div 3 tick 100)
   - Marker List window → that row → Position cell → direct input or manually move the marker
4. Call via stdio JSON-RPC with v3.1.11 binary:
   ```bash
   echo '{"jsonrpc":"2.0","id":1,"method":"resources/read","params":{"uri":"logic://markers"}}' \
     | LogicProMCP
   ```
5. **Expected response**: position is `"5.2.3.100"` (accurate). With v3.1.10 it would fall back to `"1.1.1.1"`.

**Restore procedure**: System Settings → Language & Region → Apps → Logic Pro → Korean. Restart Logic. If Logic Pro is not in the Apps list, click + → add Logic Pro → select Korean.

### 2.2 Korean 12.2 whole-bar regression (G3 both-builds guarantee)

**Scenario**: Create a normal whole-bar marker in a Korean build. Response position == `"1.1.1.1"` (canonical). T2 unit pass + T3 integration regression.

### 2.3 13-locale menu path (F1 doc verification)

With the same procedure as 2.1, confirm `Navigate → Open Marker List` works in English build.
Confirm `탐색 → 마커 목록 열기` (`Navigate → Open Marker List`) works in Korean build.
**No marker list item in the Window menu** — consistent with English reporter's report.

### 2.4 Behavior change (`"17 2"` moved to invalid) regression

```bash
# 1-3 component input is fallback in v3.1.11 (prevents silently navigating to wrong bar)
# guaranteed by unit tests; live verification depends on reporter scenario
```

Direct simulation in live environment is difficult (Logic UI only exposes normal 4 components). T2 invalid matrix provides the guarantee.

---

## Tier 3 — NG / Honest Disclosure

| NG | Content |
|----|---------|
| **NG10** | **Sub-bar navigation** not possible. `goto_marker { name: "VOCALS" }` sees the accurate `"146.4.4.240"` in cache, but AX `gotoPositionViaBarSlider` extracts only the first component → navigates to bar 146 only. Separate PRD for v3.2 will resolve this. |
| **NG11** | **Lenient 1-3 components removed**. No Logic build uses 1-3 components. If a future build exposes abbreviated header rows → fallback `\(index+1).1.1.1` (no silent manufacturing — honest). |
| NG7 | Dot has meaning only as trailing punctuation. Mixed separator (`"1.1 1.1"`) is rejected. |
| NG8 | 1-based validation. `"0 0 0 0"` rejected (blocks manufactured data). |
| NG9 | Only ASCII digits 0-9 accepted (non-ASCII such as Arabic-Indic rejected). |

### Unverified items (revisit on user reports)

- Logic Pro 12.3+ — unreleased. Additional cases needed if AX format changes.
- Logic Pro 11.x — this project targets 12.x primarily. AX rules for 11.x unverified.
- 11 locales beyond KR/EN — code supports all 13 locales, but live real-device verification is KR/EN only.

---

## When to update this runbook

- Update Tier 1 unit count + Tier 2 scenarios when `parseMarkerListPosition` changes
- Re-run Tier 2 in full when a new Logic version is released
- Add a row to the Tier 2.3 table when a new locale is reported

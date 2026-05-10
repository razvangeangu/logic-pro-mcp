# T9 — live-verify-v3.2.0 Runbook

**Status**: Todo
**Depends on**: T0 result + T1-T7 integration
**Size**: S
**PRD**: AC-7.6

## Deliverable

`docs/live-verify-v3.2.0.md` (3-tier runbook). Format follows `docs/live-verify-v3.1.11.md`.

## Structure

```markdown
# Live Verification Runbook — v3.2.0 (NG10 + Provenance)

## Tier 1 — Automated
- swift test --no-parallel → 1074+ PASS
- swift build -c release → 0 warnings
- swift test --filter parseFourComponentPosition / MarkerStateCodable / gotoPosition
- testServerVersionMatchesPackagingArtefacts → 3.2.0
- brew test logic-pro-mcp

## Tier 2 — Live (Logic Pro 12.2 device)
### 2.1 4-component dialog precision nav (NG10 fix validation)
### 2.2 Slider partial fallback (empty project)
### 2.3 Marker provenance — `goto_marker` fallback uncertainty
### 2.4 Codable backward compat — v3.1.x snapshot decode
### 2.5 IME scenarios (T0 results permanently recorded)

## Tier 3 — NG / Honest Disclosure
- NG10 closed (closed in this release)
- NG-v3.2-1: Logic 11.x unverified
- NG-v3.2-2: SMPTE precision nav requires separate mmc.locate
- NG-v3.2-3: IME OS changes may require re-validating Tier mitigation
```

## T0 Spike Results Permanent Record Location (Tier 2.5)

```markdown
### 2.5 IME Scenarios (T0 spike permanent record)

| Scenario | Logic build | IME | T0 result | Implementation Tier | Live verification |
|----------|------------|-----|-----------|--------------------|--------------------|
| S1 | English 12.2 | ABC | [PASS/FAIL — filled in T0] | Tier X | [re-verified PASS/FAIL] |
| S2 | Korean 12.2 | ABC | [...] | Tier X | [...] |
| S3 | Korean 12.2 | Hangul | [...] | Tier X | [...] |
```

## Acceptance Criteria

- **AC-T9.1**: `docs/live-verify-v3.2.0.md` created
- **AC-T9.2**: 3 Tier structure + T0 results permanently recorded in Tier 2.5
- **AC-T9.3**: NG-v3.2 honest disclosure section
- **AC-T9.4**: English markdown, "When to update this runbook" section included

## Out of Scope

- Live device verification automation — permanently manual
- Other locale scenarios (FR/DE/JA etc.) — this runbook covers KR/EN only

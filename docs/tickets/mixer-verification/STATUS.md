# Pipeline Status: mixer-verification-honesty (Issues #10–13 → v3.4.6)

> **Historical record (v3.4.6 cycle, closed 2026-06-09).** Counts and coverage figures below are as-of-then evidence; current release-candidate verification figures live in `README.md` § Verification and `docs/live-verify-v3.6.0.md`.

**PRD**: docs/prd/PRD-mixer-verification-honesty.md (v0.2 Approved)
**Tickets**: docs/tickets/mixer-verification/TICKETS.md
**Size**: XL · **Phase at close**: 14 (post-release CI coverage uplift ready)
**Historical baseline**: 1208 tests green. Stack: Swift 6.2/SPM, `swift test --no-parallel`, coverage hard gate region>=70/line>=78; line>=90 tracked target. Latest local coverage at that cutoff: 73.62% region / 81.06% line.
**Authority**: Isaac approved push/release/docs/issue replies and conditional issue close on 2026-06-09. Full strict live E2E completed in Phase 12.

## Tickets

| Ticket | Title | Tier | Status | Review | Notes |
|--------|-------|------|--------|--------|-------|
| A2 | ScripterChannel HC + range guard | T1 | **Adopted** | green | concurrent-session, 검증완료 |
| A3 | set_plugin_param State-B select gate | T1 | **Adopted** | green | P1-2 |
| A1 | MCU_TRACE raw-MIDI trace | T1 | **Done** | green(8) | #10. wiring은 E1 live E2E 검증(codex P1) |
| A4 | set_pan honest relative disclosure | T1 | **Done** | green(1168) | P1-5. pan_write_mode:"relative_vpot" (C2 docs 남음) |
| B1 | logic://mixer provenance | T1 | **Done** | green(1166) | #11. data_source+triplet+alias. 공유 lastFeedbackAgeMs helper |
| B2 | logic://mixer/{strip} envelope | T1 | **Done** | green(1166) | #11. bare→envelope+data_source |
| H1 | MIDIEngine restart-safe inbound | T1 | **Done** | green(1155) | P1-6. stop() finish 제거→deinit only |
| H2 | AX coord fallback hardening | T1 | **Done** | green(1174) | P2-5. AXHelpers.point/size(fromRawAttribute:) 4 site fail-closed + 6 tests |
| D1 | EndToEndTests stale 제거 | T1 | **Done** | green(1174) | P1-1. 10 stale cmd → isError/structured assertion |
| D2 | live-e2e-test.py stale 제거 | T1 | **Done** | py_compile OK | P1-4. tool-read→resource read 전량. live-run=operator |
| C2 | docs accuracy | T1 | **Done** | - | G6. TROUBLESHOOTING channels_exhausted/#10/#11/#12/MCU_TRACE + API.md mixer/strip/set_plugin_param/data_source |
| C1 | version finalize 3.4.6 (7면) | T1 | **Released** | green | ServerConfig/manifest/Formula version+sha256/install.sh/README/CHANGELOG/ResourceProvider/test banners synced to 3.4.6. Stable GitHub Release `v3.4.6` published as ADHOC with SHA256 metadata and macOS 14/15 install validation. |
| E1 | T0 라이브 스파이크 | gate | **Done** | SPIKE-REPORT.md | 초기 스파이크에서 #10 echo_timeout/#11 stale/getMixerArea broken 확인 → 2026-06-09 후속 AX dump로 matcher 확정 |
| F1/F2/F3 | AX 독립 되읽기 | T2 | **Done** | green(1192)+live | Logic 12.2 mixer AX matcher 복구, AX fader taper 보정, echo timeout 후 `verify_source:"ax_readback"`, `plugins_source:"ax"` |
| G1/G2/G3 | opt-in insert_plugin | T3 | **Done** | green(1192)+live | L2 `confirmed:true`, Gain/Compressor/Channel EQ allowlist, occupied-slot fail-closed, AX slot readback 검증 |

## 구현 순서 (T1)
A1 → H1 → H2 → A4 → B1 → B2 → D1 → D2 → C2 → (E1 스파이크) → F* → G* → C1(버전) → 최종리뷰 → E2E → 이슈답글/닫기.
> 각 티켓 Red→Green→Refactor + Incremental Review(슬라이딩 윈도우) + 전체 테스트.

## Review History

| Phase | Round | Verdict | P0 | P1 | P2 | Notes |
|-------|-------|---------|----|----|-----|-------|
| 2 (PRD) | 1 | guardian HAS ISSUE / boomer PROCEED_W_CAUTION | 0 | 0 | 4 | §13 R1-R11로 해소 → v0.2 Approved |
| 4 (티켓) | 1 | codex gpt-5.5 xhigh PROCEED_WITH_CAUTION | 0 | 5 | 4 | H1/H2/B1 버그 확정. 티켓별 테스트성 갭 → 구현 시 반영(B1 helper, C1 census 확장, C2/D 명세, H2 testable, A1 wiring=E1) |
| 6 (최종) | 1 | codex gpt-5.5 xhigh RECONSIDER | 1 | - | 1 | P1 set_plugin_param non-numeric value→0 coercion(select 전 strict parse+range+param bound으로 수정) · P2 stop() onReceive 잔존(nil 처리) |
| 6 (최종) | 2 | codex 수렴 — P1/P2 fixed 확인 + doc gap(plaintext vs State C) doc로 정정 | 0 | 0 | 0 | PROCEED. 1177 green. |
| 7 (후속 구현) | 1 | local TDD + live Logic 12.2 targeted E2E | 0 | 0 | 0 | #10/#11/#12/#13 implemented. 1192 green + release build + targeted live E2E pass. |
| 8 (hard verification) | 1 | local deterministic + coverage + live Logic 12.2 targeted E2E | 0 | 0 | 0 | `VERIFICATION-2026-06-09.md`. Initial full-suite flake in `testProductionMCUTransportReceiveParsesFeedbackEvents` fixed with bounded receive wait; then 1192 green, release build pass, coverage 70.40% region / 77.78% line, targeted #10-#13 live checks pass. |
| 9 (CI/release guard) | 1 | local TDD + CI coverage rehearsal | 0 | 0 | 0 | Coverage gate uses writable temp profile fallback, reports LLVM profile runtime warnings, fail-closes on profdata/report parsing plus region>=70/line>=77 with line>=90 target, RC tags publish as prerelease, Scripts one-off harnesses removed. 1197 green, coverage 70.40% region / 77.78% line. |
| 10 (release publication) | 1 | GitHub Release workflow + metadata/SHA verification | 0 | 0 | 0 | `v3.4.5` published. Release run `27183025739` success; jobs `build`, `validate-install (macos-15)`, `validate-install (macos-14)` passed; assets 5 uploaded; `RELEASE-METADATA.json` = ADHOC; Formula sha256 synced to published universal tarball. |
| 11 (issue closure) | 1 | final targeted live E2E + GitHub state verification | 0 | 0 | 0 | #10-#13 closed as completed after final verification; `gh issue list --state open` returned `[]`; each issue view returned `closed:true`, `state:"CLOSED"`. |
| 12 (full live attestation) | 1 | strict live E2E + fresh targeted #10-#13 | 0 | 0 | 0 | Fixed live harness cycle-cache timing with bounded wait. `LOGIC_PRO_MCP_STRICT_LIVE=1 Scripts/live-e2e-test.sh` -> 285 passed, 0 skipped. Fresh targeted #10/#11/#12/#13 re-run passed with slot 6 insert/occupied guard. |
| 13 (v3.4.6 release sync) | 1 | version/doc/Formula release alignment + GitHub Release workflow | 0 | 0 | 0 | `v3.4.6` published from commit `4592248`. Local gates: py_compile pass, Formula syntax pass, VersionConsistency pass, coverage 1197 green at 70.81% region / 78.32% line, release build pass. Release run `27186085967` success; jobs `build`, `validate-install (macos-15)`, `validate-install (macos-14)` passed; assets 5 uploaded; Formula sha256 synced to published universal tarball `6420274b...`. |
| 14 (coverage gate uplift) | 1 | local deterministic + coverage + production-ready review | 0 | 0 | 0 | Coverage gate raised to region>=70/line>=78 and guarded by contract tests. Added focused tests for AXMouseHelper, AX-backed Library selection, control-bar lookup, accessibility validation, and ProcessUtils. Local gates: `swift test --no-parallel` 1208 passed; coverage 1208 green at 73.62% region / 81.06% line. |

## 최종 상태 (2026-06-09, v3.4.6 release/docs sync verified)
- **#10 fixed**: MCU echo timeout 후 AX fader readback으로 State A 반환. Live: `verify_source:"ax_readback"`, `observed_ax:0.33777777777777773` for requested `0.36` (tolerance 0.04), `observed_mcu:null`.
- **#11 fixed**: `logic://mixer`가 Logic 12.2 mixer AX poll로 갱신됨. Live post-write readback: `data_source:"ax_poll"`, track 0 `volume:0.33777777777777773`.
- **#12 fixed at snapshot level**: channel strip `plugins[]` is populated from AX with `plugins_source:"ax"` and bypass/name fields. Fresh live snapshot: `Gain`, `Gain`, `Gain`, `Gain`, `Gain`, `Drum Machine Designer`. Full per-parameter value readback remains future work.
- **#13 fixed for opt-in insert**: `insert_plugin` is exposed only with L2 `confirmed:true`, stock allowlist, occupied-slot refusal, and AX slot readback. Fresh live: slot 6 Gain insert returned `verified:true`, `verify_source:"ax_plugin_slot"`; re-run on occupied slot failed closed with `slot_occupied`. Arbitrary `set_plugin_param insert:N` remains future work.
- **Verification**: focused TDD RED/GREEN for fader taper edge; release evidence remains `swift test --no-parallel` -> **1197 tests passed**, release build passed, coverage **70.81% region / 78.32% line**, strict live E2E -> **285 passed, 0 skipped, 0 failed**, targeted live E2E against Logic Pro 12.2 release binary -> all issue checks passed. At the v3.4.6 post-release cutoff, coverage uplift evidence was **1208 tests passed** with coverage TOTAL **73.62% region / 81.06% line**. Full release evidence: `docs/tickets/mixer-verification/VERIFICATION-2026-06-09.md`, `docs/live-verify-v3.4.6.md`, and `docs/releases/v3.4.6.md`.
- **Release boundary**: tag `v3.4.6` points at release commit `4592248`; `main` and `origin/main` pointed at post-release docs sync commit `22362d4` during this closeout. GitHub Release `v3.4.6` was published as stable (`draft=false`, `prerelease=false`, latest at publication) with 5 assets. Release workflow run `27186085967` passed build plus macOS 14/15 install validation. `v3.4.5` remains the functional mixer-fix release; `v3.4.6` is the evidence/packaging alignment release.
- **Issue close verified**: #10 https://github.com/MongLong0214/logic-pro-mcp/issues/10#issuecomment-4656122876 · #11 https://github.com/MongLong0214/logic-pro-mcp/issues/11#issuecomment-4656124282 · #12 https://github.com/MongLong0214/logic-pro-mcp/issues/12#issuecomment-4656125708 · #13 https://github.com/MongLong0214/logic-pro-mcp/issues/13#issuecomment-4656126616. `gh issue list --state open` returned `[]`.
- **Post-release CI/release guard**: coverage now routes fallback profile output to writable temp paths, reports LLVM profile runtime warnings, hard-gates on profdata/report parsing plus region>=70/line>=78 while reporting line>=90 target, and marks hyphenated release tags as GitHub prereleases.

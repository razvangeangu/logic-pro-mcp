# Pipeline Status: mixer-verification-honesty (Issues #10–13 → v3.4.5)

**PRD**: docs/prd/PRD-mixer-verification-honesty.md (v0.2 Approved)
**Tickets**: docs/tickets/mixer-verification/TICKETS.md
**Size**: XL · **Current Phase**: 9 (v3.4.5 source/tag pushed; stable artifact publication blocked)
**Baseline**: 1197 tests green. Stack: Swift 6.2/SPM, `swift test --no-parallel`, coverage hard gate region>=70/line>=77; line>=90 tracked target.
**Authority**: Isaac approved push/release/docs/issue replies on 2026-06-09. Full destructive 200+ live E2E remains separate.

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
| C1 | version finalize 3.4.5 (7면) | T1 | **Source/tag done; artifact blocked** | green | ServerConfig/manifest/Formula version/install.sh/README/CHANGELOG/ResourceProvider/test banners synced to 3.4.5. Stable GitHub Release is blocked until notarization secrets are configured; Formula sha256 is filled after published artifact. |
| E1 | T0 라이브 스파이크 | gate | **Done** | SPIKE-REPORT.md | 초기 스파이크에서 #10 echo_timeout/#11 stale/getMixerArea broken 확인 → 2026-06-09 후속 AX dump로 matcher 확정 |
| F1/F2/F3 | AX 독립 되읽기 | T2 | **Done** | green(1192)+live | Logic 12.2 mixer AX matcher 복구, AX fader taper 보정, echo timeout 후 `verify_source:"ax_readback"`, `plugins_source:"ax"` |
| G1/G2/G3 | opt-in insert_plugin | T3 | **Done** | green(1192)+live | L2 `confirmed:true`, Gain/Compressor/Channel EQ allowlist, occupied-slot fail-closed, AX slot readback 검증 |

## 구현 순서 (T1)
A1 → H1 → H2 → A4 → B1 → B2 → D1 → D2 → C2 → (E1 스파이크) → F* → G* → C1(버전) → 최종리뷰 → E2E → 이슈답글.
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
| 9 (CI/release guard) | 1 | local TDD + CI coverage rehearsal | 0 | 0 | 0 | LLVM profile write errors fail closed, profile fallback path uses writable temp, CI gate raised to region>=70/line>=77 with line>=90 target, RC tags publish as prerelease, Scripts one-off harnesses removed. 1197 green, coverage 70.79% region / 78.30% line. |

## 최종 상태 (2026-06-09, 후속 구현 검증)
- **#10 fixed**: MCU echo timeout 후 AX fader readback으로 State A 반환. Live: `verify_source:"ax_readback"`, `observed_ax:0.33777777777777773` for requested `0.36` (tolerance 0.04), `observed_mcu:null`.
- **#11 fixed**: `logic://mixer`가 Logic 12.2 mixer AX poll로 갱신됨. Live post-write readback: `data_source:"ax_poll"`, track 0 `volume:0.33777777777777773`.
- **#12 fixed at snapshot level**: channel strip `plugins[]` is populated from AX with `plugins_source:"ax"` and bypass/name fields. Live snapshot: `Gain`, `Gain`, `Drum Machine Designer`. Full per-parameter value readback remains future work.
- **#13 fixed for opt-in insert**: `insert_plugin` is exposed only with L2 `confirmed:true`, stock allowlist, occupied-slot refusal, and AX slot readback. Live: Gain insert returned `verified:true`, `verify_source:"ax_plugin_slot"`; re-run on occupied slot failed closed with `slot_occupied`. Arbitrary `set_plugin_param insert:N` remains future work.
- **Verification**: focused TDD RED/GREEN for fader taper edge; `swift test --no-parallel` → **1192 tests passed**; `swift build -c release` → passed; `swift test --enable-code-coverage --no-parallel` → **1192 tests passed**; coverage TOTAL **70.40% region / 77.78% line**; targeted live E2E against Logic Pro 12.2 release binary → all issue checks passed. Full evidence: `docs/tickets/mixer-verification/VERIFICATION-2026-06-09.md`.
- **Release boundary**: `main` and tag `v3.4.5` are pushed. The stable release workflow run `27178878939` is blocked before artifact publication because `MACOS_CERT_BASE64` is empty and stable ADHOC releases are intentionally forbidden. Published SHA256/Formula lockstep is verified only after the workflow is rerun with notarization secrets and publishes artifacts.
- **Issue comments posted**: #10 https://github.com/MongLong0214/logic-pro-mcp/issues/10#issuecomment-4655332572 · #11 https://github.com/MongLong0214/logic-pro-mcp/issues/11#issuecomment-4655332671 · #12 https://github.com/MongLong0214/logic-pro-mcp/issues/12#issuecomment-4655332753 · #13 https://github.com/MongLong0214/logic-pro-mcp/issues/13#issuecomment-4655332836.
- **Post-release CI/release guard**: coverage now fails closed on LLVM profile write errors, routes fallback profile output to writable temp paths, hard-gates region>=70/line>=77 while reporting line>=90 target, and marks hyphenated release tags as GitHub prereleases.

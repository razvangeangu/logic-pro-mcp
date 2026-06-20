# Locale-Agnostic AX Policy

Logic Pro MCP must not treat localized UI text as proof that a UI mutation succeeded. Localized labels are compatibility hints only.

## Matching Order

1. Prefer structural AX relationships: role, subrole, direct children, selected children, parent/child context, and stable layout position.
2. Prefer stable AX identifiers where Logic exposes them.
3. Use geometry only to anchor a known control to a known context, such as a plugin popup near the requested insert slot.
4. Use localized title/description text only when Logic exposes no stable non-localized handle.
5. Keep all unavoidable localized text in `AXLocalePolicy`.
6. On mutating paths, State A requires independent readback after the write.

## Centralized Compatibility Labels

`AXLocalePolicy` currently owns English/Korean labels for:

Menu / dialog / confirmation surfaces (PR #98):

- View > Show Mixer
- Window > Hide All Plug-in Windows
- Edit > Undo prefix
- Go to Position dialog title
- Cancel buttons
- Save/OK confirmation buttons
- Plugin format leaves: Stereo, Mono, Mono->Stereo, Dual Mono

Read-only locator / state-extraction surfaces (issue #60 Phase 2):

- Transport control identification (read-only `TransportState` extraction): Play, Record (with a separate record-arm exclusion guard), Cycle/Loop, Metronome/Click.
- Transport text-field labels: Tempo (incl. `bpm`), playhead Position.
- Control-bar AXGroup description: Control Bar / 컨트롤 막대.
- Control-bar slider descriptions: bar (마디), beat (비트), tempo (템포/bpm for the exact `findTempoSlider` locator; tempo/템포 only for the read-only extraction loop — two deliberately distinct label sets).
- Track-header read-only state extraction buttons: Mute (음소거), Solo (솔로), Record (Rec / 녹음 활성화 / 레코드 활성화).
- Per-track record-enable AXCheckBox description: 녹음 활성화 / Record Enable / Record (matched verbatim/case-sensitive at the call site).
- Plugin Setting AXPopUpButton value tokens: Preset / 프리셋 / Default / 기본 (matched verbatim/case-sensitive substring at the call site).

These labels are allowed because each use is either best-effort cleanup/reveal, a read-only locator/state read, or followed by independent file, project, track, plugin, or inventory readback. The issue #60 additions are all read-only identification helpers and introduce no new State-A success path: they preserve the EXACT label tokens, token order, and match semantics (`.contains` vs verbatim equality vs whitespace-free `.exactStrict`) of the call sites they replaced.

### Match-mode note

`AXLocalePolicy.MatchMode.exactStrict` was added in Phase 2 to model the structural control-bar / track-header locators that historically compared the AX description verbatim (`desc == "마디"`), i.e. without the whitespace trimming that `.exact` applies. Centralizing those onto `.exact` would have widened behavior, so `.exactStrict` preserves it exactly. Two call sites (the record-enable checkbox and the plugin Setting popup) require case-sensitive matching and therefore iterate over `LabelSet.labels` with verbatim `==` / `contains` rather than a policy match mode.

## Adding New Labels

- First try to solve the lookup structurally.
- If a localized label is unavoidable, add it to `AXLocalePolicy` with a rationale.
- Add deterministic tests for English and Korean at minimum.
- Do not infer State A from the click itself.
- Include a failure mode that returns State B/C when readback is unavailable or ambiguous.

## Known Remaining Surfaces

The locale-agnostic epic (#60) is **not closed**. The following localized text
surfaces are still pending and require live EN+KO E2E against real Logic Pro to
confirm State A on their respective paths:

1. **AppleScript / System Events menu literals** — `AccessibilityChannel`
   contains many menu-addressing strings (e.g. `트랙 → 트랙 삭제`,
   `다른 이름으로 저장…`, `탐색 → 이동 → 위치…`, `파일 → 가져오기 → MIDI 파일…`,
   `편집 → 이동 → 재생헤드로`, `로케이터 설정…`, the track-creation menu map, the
   plugin-insert menu chains, and rename-track menu names). These are embedded in
   `osascript` source and addressed by System Events text, so they cannot move to
   a Swift `LabelSet` without rewriting the menu-click mechanism — a behavior
   change, deferred. They must remain guarded by post-action readback.
2. **`looksLikeTransportContainer` keyword aggregate** (`AXLogicProElements`) —
   a transport-detection heuristic scanning a multi-token keyword list. It is a
   classifier, not a State-A gate; centralizing its overlapping token bag without
   widening needs a dedicated audit and is deferred.
3. **Mixer / inspector / channel-strip metadata keyword scans**
   (`AXLogicProElements`: send/입력/출력/그룹/채널 모드/볼륨/패닝/바이패스/오토메이션
   etc.) — large heuristic token bags used for classification and disambiguation.
   These are read-only but interdependent; a careful, separately-tested pass is
   required to avoid changing which strips/controls are recognized.
4. **Marker-list / cell placeholder keywords** (`AXLogicProElements`:
   `마커`/`marker`, `셀`/`Cell`, marker-list window-title suffixes) — read-only
   scraping fallbacks for old Logic versions; pending.
5. **Region / track-content / track-type description keywords**
   (`AccessibilityChannel`: `리전`/region, `트랙 콘텐츠`/Track Content,
   드러머/세션 플레이어/오디오 etc.) — read-only classification, pending.

**Live verification still required** for the surfaces centralized in this pass:
each read-only locator/extractor was verified headless with injected fake
runtimes, but the actual EN vs KO AX descriptions Logic emits at runtime (control
bar group/sliders, transport controls, track Mute/Solo/Record buttons, the
record-enable checkbox, and the plugin Setting popup value) must be confirmed
against a live Logic Pro in both locales to prove the token sets still match the
real UI.

When the AX path can replace a script path, the corresponding AppleScript literal
should be migrated to a policy-owned helper.

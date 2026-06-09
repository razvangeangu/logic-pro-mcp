# Issue replies — #10–13 current status (v3.4.5)

> Current state: the `v3.4.5` source/tag is pushed and locally verified, but stable GitHub Release artifacts are not published yet. The release workflow is blocked because stable tags require notarization secrets. Do not post the "release shipped" wording below until artifact publication succeeds; use the current status comments instead.

Source tag: https://github.com/MongLong0214/logic-pro-mcp/tree/v3.4.5
Commit: https://github.com/MongLong0214/logic-pro-mcp/commit/06966f2ae341c80a72271ea0428f2b46572a0e85
Release workflow blocker: https://github.com/MongLong0214/logic-pro-mcp/actions/runs/27178878939
Verification: `docs/live-verify-v3.4.5.md` and `docs/tickets/mixer-verification/VERIFICATION-2026-06-09.md`

Posted current-status comments:

- #10: https://github.com/MongLong0214/logic-pro-mcp/issues/10#issuecomment-4655332572
- #11: https://github.com/MongLong0214/logic-pro-mcp/issues/11#issuecomment-4655332671
- #12: https://github.com/MongLong0214/logic-pro-mcp/issues/12#issuecomment-4655332753
- #13: https://github.com/MongLong0214/logic-pro-mcp/issues/13#issuecomment-4655332836

---

## Current Status #10

Hi @thomas-doesburg,

Current source/tag update: your diagnosis was right, and the fix is merged on `main` and tagged as `v3.4.5`. Stable GitHub Release artifacts are not published yet because the release workflow correctly blocks stable tags without notarization secrets.

Logic 12.2 can still omit the MCU echo for host-originated fader writes. The new behavior does not pretend that echo exists: `set_volume` falls back to an independent AX fader readback when the MCU echo times out. If the AX-observed value matches the requested target within tolerance, the write resolves to State A with `verify_source:"ax_readback"` and `observed_ax`.

Live verification on Logic Pro 12.2:

```text
logic_mixer set_volume {track:0,value:0.36}
-> success:true
-> verified:true
-> verify_source:"ax_readback"
-> observed_ax:0.33777777777777773
-> observed_mcu:null
```

`MCU_TRACE=1` is also included and writes raw MCU TX/RX frames to stderr only, so stdout remains clean JSON-RPC.

Verification gates:

- `swift test --no-parallel` -> 1192 tests passed.
- `swift build -c release` -> passed.
- `python3 -m py_compile Scripts/live-e2e-test.py` -> passed.
- `swift test --enable-code-coverage --no-parallel` -> 1192 tests passed.
- Coverage TOTAL -> 70.40% region / 77.78% line.
- Targeted live Logic Pro 12.2 #10/#11/#12/#13 checks -> passed.

Release status: source tag `v3.4.5` is pushed, but artifact publication is blocked pending notarization secrets (`MACOS_CERT_BASE64` and related Apple notarization secrets).

## Current Status #11

Hi @thomas-doesburg,

Current source/tag update: `logic://mixer` is no longer forced to stay on stale MCU connect-time state on Logic 12.2. This is merged on `main` and tagged as `v3.4.5`; stable binary artifacts are still blocked pending notarization secrets.

The AX matcher is fixed, and `logic://mixer` exposes provenance so a client can distinguish fresh AX-observed data from last-known-good cache:

```jsonc
{
  "cache_age_sec": ...,
  "fetched_at": "...",
  "data_source": "ax_poll" | "cache_stale" | "mixer_not_visible",
  "mcu_connected": true,
  "mcu_registered": true,
  "mcu_last_feedback_age_ms": ...,
  "registered": true,
  "strips": [...]
}
```

Live verification after the #10 write:

```text
logic://mixer
-> data_source:"ax_poll"
-> strips[0].volume:0.33777777777777773
```

Verification gates: `swift test --no-parallel` 1192 passed, coverage 70.40% region / 77.78% line, and targeted live Logic Pro 12.2 #11 passed.

## Current Status #12

Hi @thomas-doesburg,

Current source/tag update: the empty `plugins[]` ambiguity is fixed at the snapshot level, and `set_plugin_param` is now honest about its write/readback limits. This is merged on `main` and tagged as `v3.4.5`; stable binary artifacts are still blocked pending notarization secrets.

What changed:

- `logic://mixer` can populate insert snapshots from AX.
- Each strip can carry `plugins_source:"ax"` so a client can distinguish a real AX-observed plugin snapshot from unknown/unread plugin state.
- `set_plugin_param` returns State B `readback_unavailable` with `cc`, `applied_midi_value`, and `readback_source:"scripter_send_only"` instead of free-form text.
- Invalid value / non-numeric value / `param > 17` are rejected before track selection.
- The write is refused if the pre-write track selection is not verified.

Live verification:

```text
logic://mixer strip 0
-> plugins_source:"ax"
-> plugins:["Gain","Gain","Drum Machine Designer"]
```

Boundary: this is not full per-parameter plugin value readback. Scripter remains send-only; full parameter value readback is future work.

Verification gates: `swift test --no-parallel` 1192 passed, coverage 70.40% region / 77.78% line, and targeted live Logic Pro 12.2 #12 passed.

## Current Status #13

Hi @thomas-doesburg,

Current source/tag update: the opt-in `insert_plugin` path is merged on `main` and tagged as `v3.4.5` with the guardrails discussed. Stable binary artifacts are still blocked pending notarization secrets.

What changed:

- `insert_plugin` is not a default blind descriptor; it requires explicit Level-2 confirmation.
- Stock allowlist is enforced for the supported path.
- Occupied slots fail closed; no silent replacement.
- After insertion, Logic's AX slot is read back and the operation only returns verified when the observed plugin matches.

Live verification:

```text
insert_plugin without confirmed:true
-> confirmation_required:true

insert_plugin {track:0,slot:3,plugin_name:"Gain",confirmed:true}
-> success:true
-> verified:true
-> verify_source:"ax_plugin_slot"
-> observed_plugin_name:"Gain"

repeat same insert into occupied slot 3
-> channels_exhausted / slot_occupied
```

Boundary: arbitrary `set_plugin_param insert:N` remains future work. v3.4.5 source ships the safe insert primitive and slot readback, not a universal per-insert parameter writer.

Verification gates: `swift test --no-parallel` 1192 passed, coverage 70.40% region / 77.78% line, and targeted live Logic Pro 12.2 #13 confirmation/insert/occupied-slot checks passed.

---

## Draft Final #10 — Mixer parameter writes: adapter returns success but MCU echo times out

Hi @thomas-doesburg,

Final v3.4.5 update: your diagnosis was right, and the fix is now shipped.

The Logic 12.2 behavior is still what your probes showed: host-originated fader writes can fail to produce an MCU echo even while MCU is connected/registered and general feedback is fresh. v3.4.5 does not pretend that echo exists. Instead, `set_volume` now falls back to an independent AX fader readback when the MCU echo times out. If the AX-observed fader value matches the requested target within tolerance, the write resolves to State A with `verify_source:"ax_readback"` and `observed_ax`.

Live verification on Logic Pro 12.2:

```text
logic_mixer set_volume {track:0,value:0.36}
-> success:true
-> verified:true
-> verify_source:"ax_readback"
-> observed_ax:0.33777777777777773
-> observed_mcu:null
```

`MCU_TRACE=1` is also included in v3.4.5 and still writes raw MCU TX/RX frames to stderr only, so stdout remains clean JSON-RPC.

Release: https://github.com/MongLong0214/logic-pro-mcp/releases/tag/v3.4.5

Final verification gates:

- `swift test --no-parallel` -> 1192 tests passed.
- `swift build -c release` -> passed.
- `python3 -m py_compile Scripts/live-e2e-test.py` -> passed.
- `swift test --enable-code-coverage --no-parallel` -> 1192 tests passed.
- Coverage TOTAL -> 70.40% region / 77.78% line.
- Targeted live Logic Pro 12.2 #10/#11/#12/#13 checks -> passed.

This supersedes my earlier AX-deferral comment: the Logic 12.2 mixer AX matcher has since been fixed and live-verified.

## Final #11 — `logic://mixer` readback does not reflect post-write volume/pan

Hi @thomas-doesburg,

Final v3.4.5 update: `logic://mixer` is no longer forced to stay on stale MCU connect-time state on Logic 12.2.

The root cause ended up being the two-part failure we narrowed down: no host-write MCU echo (#10), plus a stale AX matcher for the Logic 12.2 mixer pane. The AX matcher is now fixed, and `logic://mixer` exposes provenance so a client can tell whether strips are fresh or last-known-good:

```jsonc
{
  "cache_age_sec": ...,
  "fetched_at": "...",
  "data_source": "ax_poll" | "cache_stale" | "mixer_not_visible",
  "mcu_connected": true,
  "mcu_registered": true,
  "mcu_last_feedback_age_ms": ...,
  "registered": true,
  "strips": [...]
}
```

Live verification after the #10 write:

```text
logic://mixer
-> data_source:"ax_poll"
-> strips[0].volume:0.33777777777777773
```

So the harness rule is now:

- `data_source:"ax_poll"` -> current AX-observed mixer state.
- `cache_stale` / `mixer_not_visible` -> last-known-good, do not treat as fresh.
- `mcu_connected:false` -> MCU-derived values are not trustworthy as current state.

Release and verification:

- https://github.com/MongLong0214/logic-pro-mcp/releases/tag/v3.4.5
- `swift test --no-parallel` -> 1192 passed.
- Coverage -> 70.40% region / 77.78% line.
- Targeted live Logic Pro 12.2 #11 check -> passed.

This supersedes my earlier comment that the AX readback was still gated on a future spike.

## Final #12 — Structured plugin-parameter readback / empty `plugins[]`

Hi @thomas-doesburg,

Final v3.4.5 update: the empty `plugins[]` ambiguity is fixed at the snapshot level, and `set_plugin_param` is now honest about its write/readback limits.

What shipped:

- `logic://mixer` can now populate insert snapshots from AX.
- Each strip can carry `plugins_source:"ax"` so a client can distinguish a real AX-observed plugin snapshot from unknown/unread plugin state.
- `set_plugin_param` is Honest-Contract-shaped and returns State B `readback_unavailable` with `cc`, `applied_midi_value`, and `readback_source:"scripter_send_only"` instead of free-form text.
- Invalid value / non-numeric value / `param > 17` are rejected before track selection, instead of being silently coerced or clamped.
- The write is refused if the pre-write track selection is not verified.

Live verification:

```text
logic://mixer strip 0
-> plugins_source:"ax"
-> plugins:["Gain","Gain","Drum Machine Designer"]
```

Important boundary: this is not full per-parameter plugin value readback. Scripter remains send-only, and v3.4.5 does not claim a guaranteed mapping from CC 102-119 to arbitrary plugin-window AX sliders. The shipped contract gives your harness a truthful insert-slot/name/bypass snapshot and an honest write envelope; full parameter value readback is future work.

Release and verification:

- https://github.com/MongLong0214/logic-pro-mcp/releases/tag/v3.4.5
- `swift test --no-parallel` -> 1192 passed.
- Coverage -> 70.40% region / 77.78% line.
- Targeted live Logic Pro 12.2 #12 check -> passed.

## Final #13 — `insert:N` / opt-in `insert_plugin`

Hi @thomas-doesburg,

Final v3.4.5 update: the opt-in `insert_plugin` path is now shipped with the guardrails we discussed.

What shipped:

- `insert_plugin` is not a default blind descriptor; it requires explicit Level-2 confirmation.
- Stock allowlist is enforced for the supported path.
- Occupied slots fail closed; no silent replacement.
- After insertion, Logic's AX slot is read back and the operation only returns verified when the observed plugin matches.

Live verification:

```text
insert_plugin without confirmed:true
-> confirmation_required:true

insert_plugin {track:0,slot:3,plugin_name:"Gain",confirmed:true}
-> success:true
-> verified:true
-> verify_source:"ax_plugin_slot"
-> observed_plugin_name:"Gain"

repeat same insert into occupied slot 3
-> channels_exhausted / slot_occupied
```

Boundary: arbitrary `set_plugin_param insert:N` is still future work. The Scripter path addresses the selected track's Scripter CC range; targeting arbitrary insert-slot parameter windows needs a separate plugin-window AX path. v3.4.5 ships the safe insert primitive and slot readback, not a universal per-insert parameter writer.

Release and verification:

- https://github.com/MongLong0214/logic-pro-mcp/releases/tag/v3.4.5
- `swift test --no-parallel` -> 1192 passed.
- Coverage -> 70.40% region / 77.78% line.
- Targeted live Logic Pro 12.2 #13 confirmation/insert/occupied-slot checks -> passed.

---

## Historical 2026-06-08 drafts (superseded)

> 2026-06-09 note: this file preserves the first-pass reply drafts. Current status is in `STATUS.md`; the follow-up implementation supersedes the AX/getMixerArea deferral claims below.

> Original drafting tone: honest-contract, matching prior maintainer replies. These drafts were based on the 1177-test first pass and live Logic 12.2 spike; do not treat the deferral paragraphs as current after the 2026-06-09 follow-up.

---

## #10 — Mixer parameter writes: adapter returns success but MCU echo times out

Hi @thomas-doesburg,

Your probe results land exactly where the recalibration pointed, and I've now reproduced and instrumented it on my side. Confirmation + what's shipping:

**Your conclusion holds — it's a Logic 12.2 host-write echo regression, not setup.** On a live 12.2 session here, `set_volume {track:0}` returns `verified:false, reason:"echo_timeout_500ms", observed:null` while `mcu_connected:true` and general MCU feedback is flowing (the strips even carry Logic's connect-time-synced fader positions). So the pairing is healthy; Logic simply does not emit a fader pitch-bend / V-Pot echo for **host-originated** writes. Registration, bank-offset, and the 1000 ms timeout ceiling can't recover an echo that never leaves Logic — exactly as you found.

**`MCU_TRACE` is landing in 3.4.5** — the diagnostic I owed you. `MCU_TRACE=1` dumps every outbound/inbound MCU frame to **stderr** (`MCU TX: …` / `MCU RX: …`), *pre-decode* (so even frames we don't recognise show up — the point is proving "nothing came back", not "nothing recognised"), and it bypasses the log rate-limiter so the 25 ms poll cadence doesn't collapse it. stdout stays clean JSON-RPC.

```bash
MCU_TRACE=1 /opt/homebrew/Cellar/logic-pro-mcp/<3.4.5>/bin/LogicProMCP
```

Issue one `set_volume` and you'll see the outbound fader bytes with (per our shared hypothesis) zero inbound pitch-bend after them. If you can attach that trace it nails the regression to the byte.

**On the real fix (verification without echo) — honest status.** The right answer is an echo-independent readback so a write can resolve to State A even when Logic won't echo. The natural source is the AX mixer scrape we already have (`defaultGetMixerState` reads the fader `AXSlider`, value is normalized 0–1, 0 dB ≈ 0.785 — so no dB conversion needed). **But** the live spike turned up a second 12.2 problem: our `getMixerArea` (matches an AX element with `identifier=="Mixer"`) does **not** locate the 12.2 mixer pane — `logic://tracks` polls `ax_live` fine, but `logic://mixer` never AX-populates (`fetched_at:null`). So the AX fader read is currently dead on 12.2, which is also why the cache is MCU-echo-only. Restoring it needs a one-time AX-tree inspection (with Accessibility granted) to find the correct matcher; that's the gating spike and it unblocks the echo-independent verify. Tracked openly in the repo's spike report.

Net for 3.4.5: `MCU_TRACE` to confirm + the State B envelope stays honestly unverified (don't flip your flag on it — which you already don't). The echo-independent verify is the next milestone, gated on the AX spike above. Thanks again for the rigorous probes — they're what made this precise.

— Isaac

---

## #11 — `logic://mixer` readback does not reflect post-write volume/pan

Hi @thomas-doesburg,

Companion update, with a correction I owe the thread and concrete shipping changes.

**What's landing in 3.4.5 — provenance on the wire.** `logic://mixer` now carries the fields you need to decide whether to trust a read, instead of you having to infer it:

```jsonc
{
  "cache_age_sec": …, "fetched_at": …,
  "data_source": "ax_poll" | "cache_stale" | "mixer_not_visible",  // strip freshness
  "mcu_connected": true, "mcu_registered": true,
  "mcu_last_feedback_age_ms": 1234,
  "registered": true,        // one-release alias of mcu_registered
  "strips": [ … ]
}
```

Trust rule, now documented: if `data_source` is `cache_stale`/`mixer_not_visible` or `mcu_connected:false`, treat `strips` as last-known-good, not current. `logic://mixer/{strip}` gets the same envelope (it used to return a bare object with no freshness signal).

**Correction to my earlier framing.** I previously said `logic://mixer` is *exclusively* MCU-echo-derived. That's not quite right and the spike proved it: the strip array has **two** writers — MCU echo *and* a periodic AX scrape (`StatePoller` → `mixer.get_state`). The catch on **Logic 12.2** specifically: that AX scrape is currently broken — `getMixerArea` doesn't find the 12.2 mixer pane (live: `logic://tracks` is `ax_live` and fresh, but `logic://mixer` stays `fetched_at:null` even with the Mixer open). So in practice, on 12.2, the cache falls back to MCU echo only — and since host-write echo doesn't arrive (#10), a post-write read shows the pre-write (connect-sync) value. I reproduced your exact symptom: after `set_volume {track:0, value:0.4}`, a re-read still shows the old value.

**So #11's root cause is now precise:** no host-write echo (#10) **and** the AX mixer read is down on 12.2. The provenance fields above make that honest on the wire today; the durable fix (restore the AX mixer read so readback works without echo) is gated on the same one-time AX-tree spike described in #10. Until then, `data_source` tells your harness exactly when not to trust a strip.

Thanks for holding the line on "the readback has to be trustworthy on its own" — that's exactly the contract these fields encode.

— Isaac

---

## #12 — Structured plugin-parameter readback (set_plugin_param write-only; plugins:[] empty)

Hi @thomas-doesburg,

Three concrete changes for 3.4.5 plus an honest read on the two options you proposed.

**1. `set_plugin_param` is now Honest-Contract-shaped (write-half fixed).** It was returning a free-form string and silently clamping out-of-range values while echoing the original. As of 3.4.5 a routed write returns a proper HC envelope — State B `readback_unavailable` with `{insert, param, cc, applied_midi_value, requested, readback_source:"scripter_send_only"}`. Out-of-range / non-numeric / `param>17` inputs are now **rejected up front** (before the track-select side effect) instead of being silently coerced to 0 and written, and the write is **refused** if the pre-write track-select came back unverified (State B) so it can't land on the wrong track. So even before readback exists, the write is honest about exactly what it did — or honest about refusing.

**2. Option (1) — per-insert Scripter echo — is not feasible, and I'd rather tell you than have you wait on it.** The Scripter transport is structurally send-only (the virtual MIDI port is created send-only; there's no receive path), and there's no shipped Scripter feedback script. A param echo would require a new bidirectional port + an authored, operator-installed feedback script, and even then it'd be a normalized 0–1 value with no parameter-name semantics. It's the wrong shape to build on.

**3. Option (2) — AX `plugins[]` snapshot — is the right path, but it's gated on the same Logic 12.2 AX blocker as #10/#11.** Populating `plugins[]` needs AX access to the mixer pane to enumerate insert slots, and the live spike showed our `getMixerArea` doesn't locate the 12.2 mixer pane right now. To be precise about the wire: `plugins[]` still serializes as an empty `[]` today (no per-array provenance marker yet) — I've documented it as a known gap in the docs (TROUBLESHOOTING/API) so it isn't *unexplained*, but a parser can't yet distinguish "mixer not visible" from "genuinely no plugins" at the `plugins[]` level; that's a follow-up (a `plugins_source` marker) alongside the real fix. Once the one-time AX-tree spike fixes the mixer matcher, the names-only snapshot (`[{insert, name, isBypassed}]`) becomes tractable, and that's what gives your harness a stable index map to verify EQ/compressor writes against. Full per-parameter *value* readback is a further step — the blind Scripter CC index (0–17 → CC 102–119) has no guaranteed 1:1 mapping to an AX slider, so I want to be upfront that the honest first deliverable there is a best-effort labeled snapshot, not a guaranteed State A.

So: write-half is honest now; the readback you asked for is the AX snapshot, queued behind the mixer-AX spike that also unblocks #10/#11.

— Isaac

---

## #13 — Write-side gaps: set_plugin_param beyond insert:0, and opt-in plugin-insert (Gain) for gain-staging

Hi @thomas-doesburg,

Great use case — gain-staging relocation is exactly the kind of "apply a real decision" workflow worth supporting. Two honest answers plus the design I'm committing to.

**On `insert:N`:** this isn't a gate I can just widen. The Scripter path addresses parameters via CC 102–119 on the single Scripter MIDI-FX instance on the selected track — there's no wire-level way for it to target "the plugin in insert slot N." So `insert:N` is a *missing mechanism*, not a one-line relaxation. The deterministic way to do it is to focus insert N's plugin window and drive it via AX — which lands it on the same AX path as below.

**On `insert_plugin`:** one correction first — it was removed deliberately a while back (the docs say v2.2; the actual removal commit lands around v2.3.0), and for the reason you'd want: every channel returned "not implemented", so the descriptor was lying to callers. I'm not going to reintroduce that. What I *am* committing to (design is written up in the PRD under **US-8 / §13**) is the opt-in path you sketched, with guardrails:

- **off by default**, behind an explicit build-mode/approve flag — never in the default production contract;
- **stock-utility allowlist** (Gain / Channel EQ / Compressor / Noise Gate), matched by **locale-independent identifier** (Logic's plugin names are localized across 13+ locales, so name matching would be a footgun);
- **DestructivePolicy Level-2 + confirmation** (it mutates the signal chain);
- **fail-closed verification**: after inserting, read the slot back and confirm it's the requested plugin; on mismatch, **remove the slot and report** — never leave a wrong plugin in the chain (that'd repeat the v2.3.0 "lying descriptor" failure);
- occupied-slot semantics = **reject** (no silent displacement);
- and it runs only against your duplicated `.logicx`, exactly as your harness already does.

**Honest status:** both `insert:N` and `insert_plugin` depend on AX access to the mixer pane (and, for params, plugin-window AX) — and the live 12.2 spike found that our mixer AX read is currently down on 12.2 (`getMixerArea` doesn't match the 12.2 mixer pane). So this is queued behind the same one-time AX-tree spike that unblocks #10/#11/#12; I won't ship a `insert_plugin` descriptor again until there's a real, verified path behind it.

One more option worth your consideration for the verification half: since both MCU echo and AX-mixer readback are unavailable on 12.2, a **file-based readback** — saving the duplicate `.logicx` and parsing its persisted mixer/insert state — may be the most robust echo-independent path for `apply_moves` long-term. It's greenfield (Logic's doc format) so it's not in 3.4.5, but it sidesteps both broken paths.

Thanks for respecting the rc-era decision and for sketching the guardrails — they're close to what I landed on.

— Isaac

# Issue #1 Option 1 Feasibility — `LogicProMCP --install-keycmds`

> Historical record (2026-06-05 docs refresh): latest production-readiness and live E2E evidence is in `README.md`, `CHANGELOG.md`, and `docs/live-verify-v3.4.5-rc5.md`; this file remains preserved implementation context.

**Date**: 2026-05-05
**Author**: autonomous /loop investigation
**Status**: Research — **escalation recommended before implementation**

---

## 1. Goal recap

xaexx1's "Best fix" recommendation for Issue #1: a Swift CLI subcommand
that programmatically installs the Key Commands preset so users do not
have to run the Manual MIDI Learn dance for every CC binding.

Concretely, the proposed flow is:

1. `LogicProMCP --install-keycmds` quits Logic Pro.
2. Writes a properly structured `.logikcs` file into Logic's user
   preset directory.
3. Injects an "MROF" (Mackie Remote Override Format?) chunk into Logic's
   Control Surface preferences plist so the bindings actually take
   effect on next launch.
4. Re-launches Logic.

## 2. What ships with Logic 12.2

`/Applications/Logic Pro.app/Contents/Resources/Key Commands/U.S..logikcs`
is 64 099 bytes. It is **a regular XML property list** with this top
level structure:

```
<dict>
    <key>Content</key>                  → "com.apple.logic.keycommand"
    <key>KeyCommandColors</key>          → {numeric command id: color int}
    <key>KeyCommandShortNames</key>      → {numeric command id: short label}
    <key>LogicBinaryPreferences</key>    → <data>…840 lines of base64…</data>
    <key>TouchBarAssignments</key>       → separate dict
    <key>Version</key>                   → integer
</dict>
```

Lines 204..1052 of the file are a single base64 `<data>` blob. That
blob is the **only place the actual key/MIDI/MMC assignments live** —
the surrounding XML carries only metadata (colours and short names).

## 3. Why this blocks "Option 1" as autonomous work

`LogicBinaryPreferences` is an undocumented binary format. Two
properties make it a poor target for unattended reverse-engineering:

1. **No public schema.** Apple has not published the layout. The
   community-maintained `LogicProTagger` project decodes a small slice
   of it (track tags), but the keycmd / MIDI assignment tables inside
   the blob are not covered there. We would need to reverse the format
   from scratch — at minimum: command-id table, modifier flags,
   scancode triplets, MIDI-vs-key disambiguator byte, and the per-entry
   length prefix.
2. **Version instability.** A diff of Logic 11.1, 12.0, 12.1 and 12.2's
   `Default.logikcs` shows the blob length and several internal offsets
   change between point releases. A schema we reverse against 12.2 is
   therefore not safe to ship without a per-version probe step at
   install time, plus a refusal path on unknown versions. That probe
   step itself depends on the same RE work.

Concretely, the smallest honest plan I can write looks like:

| Phase | Effort | Risk |
|-------|--------|------|
| RE blob layout for Logic 12.2 only (single binding) | 1–2 weeks | High — need diffing scaffolding + many capture-rebuild-launch cycles |
| Generalize across modifier flags, MIDI types | +1 week | High |
| Inject + validate via Logic restart in CI | +3–5 days | Medium — Logic has no headless mode; CI must run on real macOS w/ Logic licensed |
| Maintain across Logic 12.3, 13.0… | recurring | Medium-high — every Logic update can re-break |

That is L→XL scope per CLAUDE.md, **explicit Level 2 territory** (new
binary integration with shared system state). Autonomous /loop should
not start it.

## 4. What we already shipped that addresses the same need

v3.1.6 took xaexx1's "Good" path (Option 2) instead:

* `logic_midi.send_*` accepts `port: "midi" | "keycmd"` so callers can
  drive the KeyCmd virtual port directly from a single tool call.
* Channel is now 1-based (1..16), matching Logic's UI numbering, so the
  "channel 16 → Logic shows Ch 1" bug from the report is fixed.
* `MIDIKeyCommandsChannel.healthCheck()` now emits a `manual_validation_required`
  detail that names the port (`LogicProMCP-KeyCmd-Internal`) and the
  audited coverage matrix, so an LLM agent can decide whether to
  attempt a binding instead of failing opaquely.
* `docs/SETUP.md` §4 was rewritten — the misleading "Import…" path is
  gone; the Manual MIDI Learn flow is the only documented path with
  realistic time estimates.

That covers Issue #1's actual blocker (the channel was unreachable +
the docs lied). Option 1 remains a *latency* improvement, not a
correctness fix.

## 5. Recommendation

* **Do not start Option 1 autonomously.** Ship as a v3.2.x research
  spike under explicit Level 2 approval, scoped to "RE Logic 12.2 only,
  refuse other versions" so the surface area stays bounded.
* If Isaac wants to defer it indefinitely, the alternative is xaexx1's
  Option 4 (deprecate `MIDIKeyCommands` channel as effectively
  redundant). v3.1.6's audited coverage matrix already documents that
  every preset op except `transport.capture_recording` has a non-keycmd
  path, so the deprecation cost is small and would let us drop ~480
  lines in `MIDIKeyCommandsChannel.swift` plus the KeyCmd virtual port
  publish/teardown code.

Either way, it is a strategist call, not a /loop call.

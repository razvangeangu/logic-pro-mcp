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

- View > Show Mixer
- Window > Hide All Plug-in Windows
- Edit > Undo prefix
- Go to Position dialog title
- Cancel buttons
- Save/OK confirmation buttons
- Plugin format leaves: Stereo, Mono, Mono->Stereo, Dual Mono

These labels are allowed because each use is either best-effort cleanup/reveal or followed by independent file, project, track, plugin, or inventory readback.

## Adding New Labels

- First try to solve the lookup structurally.
- If a localized label is unavoidable, add it to `AXLocalePolicy` with a rationale.
- Add deterministic tests for English and Korean at minimum.
- Do not infer State A from the click itself.
- Include a failure mode that returns State B/C when readback is unavailable or ambiguous.

## Known Remaining Surfaces

Some AppleScript fallback snippets still contain explicit menu labels because System Events menu addressing is text-based. Those fallbacks must remain guarded by post-action readback and should be migrated to policy-owned helpers when the AX path can replace the script path.

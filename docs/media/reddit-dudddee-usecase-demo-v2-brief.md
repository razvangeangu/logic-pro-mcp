# Reddit Use-Case Demo v2 Brief

## Audience

This video is for `dudddee`, who asked for a Loom/video and said Logic is their
livelihood, so crash/failure risk is the central concern.

## Difference From v1

The first cut was a safety-caption overlay on the existing live Logic capture.
This version is rebuilt from scratch as a proof-oriented explainer:

- real Logic Pro 12.2 capture on the left;
- separate right-side proof panel;
- clear story: start safely, read first, plan first, guarded write, readback,
  boundaries, longer Loom shot list;
- no claim that the tool is universally production-safe today.

## Assets

- Render script: `docs/media/render-reddit-usecase-demo-v2.py`
- MP4: `docs/media/reddit-dudddee-usecase-demo-v2.mp4`
- Thumbnail: `docs/media/reddit-dudddee-usecase-demo-v2-thumbnail.png`
- Subtitle overlay: `docs/media/reddit-dudddee-usecase-demo-v2.ass`

The Logic UI footage comes from `docs/media/logic-pro-mcp-demo.mp4`, the existing
actual Logic Pro 12.2 capture. The proof panel is explanatory and should not be
described as a live terminal recording.

## Suggested Reddit Reply

```text
Yeah, totally fair. I would not want you to run this on a livelihood session as
the first test either.

I made a short safety-first demo cut here. It uses actual Logic Pro 12.2 footage,
but the main point is the operating model: duplicate/test project first, read the
session before acting, produce a plan before mutation, require explicit targets
for risky writes, and only call an operation successful after readback or clear
failure/uncertainty.

The longer Loom I still need to make should show one complete run:
duplicate project -> read state -> guarded action -> readback -> cleanup/undo ->
test evidence.

That is the direction I am aiming for: not "AI magic", but boring local trust.
```

## Longer Loom Shot List

1. Open a duplicate Logic project.
2. Run health/project/tracks/mixer read-only queries.
3. Show the proposed plan before mutation.
4. Run one small guarded action with explicit target and confirmation.
5. Show State A/B/C result semantics and readback.
6. Cleanup with undo or verified removal.
7. Show exact test evidence and current limitations.

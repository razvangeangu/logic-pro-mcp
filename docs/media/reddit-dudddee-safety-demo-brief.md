# Reddit Safety Demo Brief

## Audience

This cut is for a Logic Pro user who asked whether there is a Loom-style video
and said Logic is their livelihood, so they cannot risk crashes or failed
operations.

## Positioning

Do not sell this as production-safe for every session. The correct tone is:

- interest is appreciated;
- a real working session should not be the first test target;
- start on a duplicate project or disposable test session;
- the product is being built around local operation, fail-closed writes,
  readback, provenance, and honest uncertainty.

## Video Asset

- Render script: `docs/media/render-reddit-safety-demo.py`
- Output MP4: `docs/media/reddit-dudddee-safety-demo.mp4`
- Thumbnail: `docs/media/reddit-dudddee-safety-demo-thumbnail.png`
- Subtitle overlay: `docs/media/reddit-dudddee-safety-demo.ass`

The MP4 loops the existing actual Logic Pro 12.2 capture
`docs/media/logic-pro-mcp-demo.mp4`. It does not render a synthetic DAW UI.

## Suggested Reddit Reply

```text
Yeah, that is a totally fair concern. I would not want you to point this at a
livelihood Logic session as the first test either.

I made a short safety-first demo cut here from an actual Logic Pro 12.2 capture.
The basic idea is: local MCP server, duplicate/test project first, read-only
inspection before writes, explicit targets for risky operations, and readback
before calling anything successful.

The longer Loom I need to make next should show the full sequence:
duplicate project -> read state -> guarded action -> readback -> cleanup/undo
-> test evidence.

I am trying to build this around boring trust rather than "AI magic", so this
kind of skepticism is exactly the useful bar.
```

## Longer Loom Shot List

1. Open a duplicated test Logic project, not a production session.
2. Read `logic://system/health`, `logic://project/info`, `logic://tracks`, and
   `logic://mixer`.
3. Show a dry-run style plan before any mutation.
4. Run one guarded action with explicit target and confirmation.
5. Show readback and provenance fields.
6. Cleanup with undo or a verified removal path.
7. End on local test evidence and current limitations.

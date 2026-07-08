# T2 - Window Acquisition Diagnostics

## Goal

Make `window_open_failed` actionable without weakening fail-closed behavior.

## Acceptance

- [x] State C includes bounded candidate window titles.
- [x] State C includes bounded slider descriptions found in candidate windows.
- [x] State C states whether an opener action was attempted.
- [x] Payload avoids local absolute paths and private machine metadata.

## Verification

- `testNoOpenPluginWindowIsWindowOpenFailed` verifies bounded candidate window
  diagnostics.
- `testProductionOpenerRejectsOpenedWindowWithoutRequestedSlider` verifies that
  an opened window without the requested slider stays State C with
  `write_attempted:false` and candidate slider evidence.
- `swift test --filter PluginSetParamVerifiedLiveTests` passed 19/19.

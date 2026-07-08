# T1 - Production Plugin Window Opener

## Goal

Replace the no-op `set_param_verified` plugin-window opener with a production
path that opens the target insert's editor window and only proceeds after the
requested parameter slider is visible.

## Acceptance

- [x] Red fixture proves default closed-window path fails before the fix.
- [x] Production opener presses/clicks the target occupied insert slot.
- [x] Window polling accepts only a window exposing the requested slider.
- [x] `set_param_verified` reaches State A in the closed-window fixture.
- [x] Wrong-window/wrong-slider cases remain State C and do not write.

## Verification

- Red-first: `testProductionOpenerOpensClosedTargetSlotWindow` failed with the
  pre-fix no-op opener.
- `swift test --filter PluginSetParamVerifiedLiveTests` passed 19/19.
- `swift build -c release` passed.

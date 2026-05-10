# Logic Pro MCP Control Path Full Survey

Written: 2026-04-21
Target repo: `/Users/isaac/projects/logic-pro-mcp`
Purpose: Consolidate realistic control paths, constraints, and implementation priorities for building a Logic Pro MCP server into a single document.

---

## 0. Summary

To state the core point first: Logic Pro has virtually no publicly documented DAW object API comparable to Ableton Live's Python Remote Script or REAPER's ReaScript.

Therefore, building a reliable MCP server requires not betting everything on a single API. The most realistic approach is the combination below.

### Recommended combination
1. **Primary control**: `CoreMIDI + MCU/HUI + Controller Assignments`
2. **Secondary control**: `MIDI key-command assignments`
3. **Parameter layer**: `OSC Message Paths` or `Controller Assignments`
4. **UI fallback**: `AXUIElement / Accessibility API`
5. **Content layer**: `MIDI / AAF / FCPXML import-export`
6. **In-project intelligence**: `Scripter` or optional `AU/AUv3 bridge`
7. **Avoid**: `Logic Remote private protocol`, direct modification of `.logicx` internal `ProjectData`

In other words, the strongest architecture anchors the **MCP backend on MCU over CoreMIDI** and limits **AX to a supporting role for menus/dialogs/error detection**.

---

## 1. Evidence basis reflected in this document

This document consolidates three axes.

### A. Based on Apple public documentation
- Logic Pro for Mac User Guide 12.2 series
- Logic Pro release notes 12.2 series
- Core MIDI documentation
- Audio Unit / AUv3 documentation
- Accessibility / AXUIElement-related documentation

### B. Local verification results
Facts confirmed directly on this Mac:
- App install path: `/Applications/Logic Pro.app`
- Locally installed version: **Logic Pro 12.0.1**
- `NSAppleScriptEnabled = 1`
- No public `OSAScriptingDefinition` key found
- No public `*.sdef`, `*.scriptSuite`, `*.scriptTerminology` found inside the app bundle
- Standard-level queries like `get version`, `count every document` partially work in AppleScript
- Rich Logic object model (tracks/regions) not available at the AppleScript level
- `CFBundleURLTypes` contains `applelogicpro`, `logicpro` schemes
- Inside `.logicx` packages: `ProjectInformation.plist`, `MetaData.plist`, `DisplayState.plist` exist, but the core `ProjectData` is not a public plist — it is opaque binary data

### C. Facts confirmed from existing repo/operational notes
- **2026-04-08**: Even when control paths were alive, `project/info`, `transport/state`, `tracks`, and `mixer` read results were stale or inconsistent — weak truthfulness.
- **2026-04-10**: Some `project.open` failures were verify false negatives; the open verification logic was reinforced.
- **2026-04-12**: Due to Logic UI/window state corruption, cases occurred where the AppleScript document model and AX/window model were misaligned. That is, not a permissions issue but **runtime UI state mismatch** can be a real-world blocker.

These three points are critical for MCP design. In particular, they suggest **the read/verification path must be designed more carefully than the write path**.

---

## 2. Complete map of available control paths

| Path | Code-level | Logic internal object access | Bidirectional state | Stability | MCP suitability |
|---|---|---:|---:|---:|---:|
| CoreMIDI + Controller Assignments | Yes | Limited | Limited | High | Excellent |
| Mackie Control / HUI emulation | Yes | Mixer/transport focused | Good | Medium~High | Excellent |
| OSC Controller Assignments | Yes | Parameter/control focused | Possible | Medium | Good |
| MIDI Device Script / Lua / MDS | Yes | Control surface mapping | Possible | Medium | Good |
| AXUIElement / Accessibility | Code but UI layer | Visible UI focused | Possible | Medium~Low | Essential support |
| AppleScript / JXA / Apple Events | Yes | Almost none | Almost none | Low | Launch/open only |
| Logic Remote protocol | Private/undocumented | Appears rich | Likely good | Low | Not recommended |
| Scripter JavaScript | Logic-internal code | MIDI/host timing | Limited | High | Good for musical tasks |
| Audio Unit / AUv3 plugins | Yes | Plugin-internal | Host info limited | High | Good as bridge |
| Direct `.logicx` file modification | Code | Risky | None | Low | Not recommended |
| MIDI / AAF / FCPXML import-export | Yes | Offline | None | High | Good for generation/analysis |

Summary:
- **Actual control**: `CoreMIDI/MCU/HUI` at the center
- **State estimation and augmentation**: `MCU feedback + AX`
- **Content generation and exchange**: `MIDI/AAF/FCPXML + Scripter/AU`
- **AppleScript/JXA is not a primary backend**

---

## 3. Priority 1: CoreMIDI + Logic Controller Assignments

Apple's Core MIDI lets macOS apps create virtual MIDI sources/destinations and communicate as if they were hardware devices. Logic Pro can map MIDI input to Logic functions, channel strips, plugin parameters, key commands, and more via Controller Assignments.

### Why this path is strong
- Can attach reliably via a local virtual port
- Less brittle to version changes than the UI tree
- Strong for transport, mixer, smart controls, and plugin parameter control
- Maps well to MCP tool abstraction

### Possible operations
| Operation | Feasibility |
|---|---:|
| Play / Stop / Record / Cycle | High |
| Mute / Solo / Arm / Select Track | High |
| Volume / Pan / Send Level | High |
| Smart Controls | High |
| Plugin parameter control | Medium~High |
| Automation mode change | Medium~High |
| Bounce/export dialog automation | Low — requires AX |
| Region creation/move/split/edit | No direct API |
| Structured track/region list query | Limited |

### MCP implementation form example
```json
{
  "tool": "logic.transport.play"
}
```
Internally, for example:
- Send Note/CC/SysEx to a virtual MIDI port
- Logic Controller Assignments maps this to Play

### Design implications
- **Write commands are strong**
- **Weak for high-level state reads**
- Therefore, state must combine `MCU feedback`, `AX visible state`, `project/file metadata`, and `internal cache`.

---

## 4. Priority 1.5: Mackie Control / HUI Emulation

A stronger approach than simple MIDI learn is having the MCP server behave like a virtual `Mackie Control Universal` or `HUI` device. Logic Pro officially supports Mackie Control/HUI within its control surface workflow.

### Advantages
- Bidirectionality
- Fader position, LED state, scribble strip/display text feedback available
- Strong for track banking, jog wheel, plugin editing, mixer control

### Good MCP tool examples
- `logic.transport.play()`
- `logic.transport.stop()`
- `logic.transport.record()`
- `logic.mixer.set_fader(track=3, db=-6.0)`
- `logic.mixer.set_pan(track=3, pan=0.2)`
- `logic.track.bank_left()`
- `logic.track.bank_right()`
- `logic.track.select(index=5)`
- `logic.plugin.next_parameter()`
- `logic.plugin.set_current_parameter(value=0.73)`

### Design implications
- **The most practical primary backend candidate**
- Easier to handle state feedback than plain Controller Assignments
- Particularly useful for estimating `track name`, `selected bank`, and `mute/solo/fader state`.

---

## 5. OSC: Useful, but not a public object API

Logic Pro supports OSC Message Paths in Controller Assignments. Based on public documentation, the current OSC implementation centers on UDP and IPv4.

### Strengths
- More readable message expressions than MIDI
- Can design value, touch/release, and label feedback
- Easy to connect later with iPad/Web UI/remote controllers

### Limitations
- Logic does not have a general-purpose REST/OSC API
- Must be configured within a Control Surface / Controller Assignments context
- Do not expect a generic API like `/logic/play` out of the box

### Recommended uses
| Use | Assessment |
|---|---:|
| Custom mixer/plugin parameter control | Good |
| Network bridge between MCP and Logic | Good |
| State feedback | Possible |
| Fully automated project editing API | Not this |

### Design implications
- For local-only use, CoreMIDI may be simpler.
- For long-term remote control/UI extension, designing a separate OSC layer has value.

---

## 6. MIDI Device Script / MDS / Lua / Control Surface Plug-in

Logic's control surface can be extended via MIDI Device Script/MDS/Lua-based mapping or dedicated control surface profiles.

### Significance
Going one step beyond "an app that fires MIDI messages," this allows an MCP-dedicated controller to be treated as a legitimate control surface inside Logic.

### Possible strategy
```text
MCP Logic Control Surface
 - virtual MIDI input
 - virtual MIDI output
 - MDS/Lua profile or MCU profile
 - Logic Controller Assignments preset
```

### Design implications
- `MDS/Lua`, `MCU/HUI`, and `Controller Assignments preset` are more maintainable long-term than binary MDP.
- Starting the initial MVP with **MCU/HUI emulation + preset** and expanding to MDS/Lua later is the safer approach.

---

## 7. AXUIElement / Accessibility API: Supplementary but nearly essential

AXUIElement is the official API that lets assistive applications communicate with and control accessibility objects in macOS apps.

### Why AX is needed in MCP
MIDI/MCU/OSC alone is insufficient for:

| Operation | AX necessity |
|---|---:|
| Opening the Bounce dialog / filling options | High |
| Running Export / Import menus | High |
| Changing Preferences | High |
| Interacting with Project settings dialog | High |
| Reading the currently open project name | Medium |
| Reading plugin window UI | Medium~High |
| Checking menu enabled/disabled state | High |
| Detecting error/warning modals | Very high |

### Key principle
AX is a "Logic UI API" — not a "Logic object API."

Therefore, limit AX to the following uses:
1. Executing menu items
2. Auto-filling dialogs
3. Detecting errors/modals
4. Reading currently visible state
5. Supporting export/import operations that are impossible via MIDI/MCU

### Permissions
- Accessibility permission required
- For a distributed app, users must grant permission in System Settings

### Swift minimal example
```swift
import ApplicationServices

func requestAccessibilityPermission() -> Bool {
 let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
 let options = [key: true] as CFDictionary
 return AXIsProcessTrustedWithOptions(options)
}
```

### Particularly important in the repo context
Per existing operational notes, Logic has had cases where **the document model and UI/window model were misaligned**.
Therefore, AXProvider must include more than a simple action executor:
- Window observer
- Modal detector
- Timeout/retry
- Focused window validation
- Visible state extractor
- Stale cache detection

---

## 8. AppleScript / JXA / Apple Events: Do not rely on as a primary path

Generally, for AppleScript/JXA to be powerful, the app must provide a meaningful scripting dictionary (.sdef).

### Local verification conclusion
- `NSAppleScriptEnabled = 1`
- Standard Apple Event level partially works
- No public `sdef` found
- No Logic-specific track/region/mixer object model found

Therefore, the conclusion is:
- **App launch / activate / file open / quit can be expected**
- **Track/region/plugin/project structure control cannot be expected**

### What can be used
- Launch Logic
- Open `.logicx` files
- Activate the app
- Quit
- Open via Finder/NSWorkspace

### What cannot be expected
- `tracks[3].volume = -6`
- `selectedRegion.start = bar 17`
- `create software instrument track`
- `insert plugin`
- `bounce with options`

### Design implications
- Treat AppleScript/JXA as a **supplementary utility**, not a primary provider
- Limit to `project.open`, `app.activate`, `document count` checks
- When UI scripting is needed, Swift/PyObjC AX path is preferable

---

## 9. Logic Remote Protocol: Viable for research, not recommended for product backend

Logic Remote is an official app, but its protocol is not documented as a public developer API.

### Assessment
| Use | Assessment |
|---|---:|
| Personal research | Possible |
| Commercial/public MCP | Not recommended |
| Update resilience | Low |
| Policy/distribution risk | Present |

### Design implications
- Features may be attractive, but given maintenance and distribution stability, the **MCU/HUI + OSC + AX** combination is better.

---

## 10. Scripter JavaScript: Logic-internal MIDI/timing bridge

Scripter is a MIDI FX plugin inside Logic that generates/transforms MIDI using JavaScript and reads host timing information.

### Strengths
- Partial access to transport playing state, tempo, meter, cycle state
- Can generate MIDI note/CC
- Can act as a "musical automation engine" stored inside the project

### Well-suited uses
- Chord progression generation
- Drum pattern generation
- MIDI transform
- Tempo-based generative behavior
- Host timing-aware MIDI logic

### Limitations
- Cannot create tracks
- Cannot move regions
- Cannot insert plugins
- Cannot bounce/export
- Cannot control files/processes/network

### Design implications
- Scripter is better suited as an **in-project intelligence layer** than an external control backend for MCP.
- If the direction is "AI creates music and Logic responds in real time," this is extremely powerful.

---

## 11. Audio Unit / AUv3 Plugins: Strong long-term internal bridge candidate

Logic officially supports Audio Unit/AUv3 plugins. Therefore, a structure like `MCP Bridge AU` is possible.

```text
Logic Pro project
 -> MCP Bridge AU / MIDI FX / Instrument
 -> local IPC / socket / XPC
 -> MCP Server
```

### What's possible
- Audio/MIDI processing
- Exposing plugin parameters to MCP
- Connecting Logic automation lanes to MCP parameters
- Host tempo/transport-reactive generators
- Bridge endpoints stored inside the project

### What's not possible
- Creating new tracks
- Moving regions
- Inserting plugins into other channels
- Directly manipulating Logic project objects

### Design implications
- **Powerful for real-time generation/processing/reactive workflows**
- However, not a replacement for a DAW object API
- Compelling for the long-term roadmap, but `MCU/HUI` is more practical for the initial MCP core backend

---

## 12. File-Based Access: MIDI / AAF / Final Cut Pro XML

Directly manipulating `ProjectData` inside `.logicx` should be avoided — it is not a public editing format.

### Use official interchange formats instead

#### Standard MIDI File
Good uses:
- Chord progression generation
- Drum pattern generation
- Baseline generation
- MIDI CC automation candidate generation

#### Final Cut Pro XML
Good uses:
- Audio stem-based project exchange
- Post-production workflows
- Exchange including volume/pan automation

#### AAF
Good uses:
- DAW-to-DAW audio session exchange
- Multi-track audio arrangement drafts
- Post/session handoff

### Design implications
Abstract on the MCP side as follows:
- `logic.create_midi_file(...)`
- `logic.project.import_midi(path)`
- `logic.project.import_audio(path)`
- `logic.project.export_aaf(path)`
- `logic.project.export_fcpxml(path)`

Actual import/export execution mostly requires AX or key command assistance.

---

## 13. Synchronization: MTC / MIDI Clock / MMC / Ableton Link

Synchronization is different from direct control, but important for aligning external apps/devices with Logic.

| Protocol | MCP use |
|---|---:|
| MMC | Transport sync/control |
| MTC | Timecode-based follow |
| MIDI Clock | External device tempo sync |
| Ableton Link | Network beat/tempo/phase sync |
| MIDI CC/Note | Actual command execution |
| MCU/HUI | Actual control surface control |

### Design implications
- Synchronization is not a primary core scope for MCP, but useful for future multi-app/music system orchestration.

---

## 14. Permissions and Distribution Issues

| Feature | Required permissions/settings |
|---|---:|
| CoreMIDI virtual port | Usually no separate TCC required |
| AXUIElement | Accessibility permission |
| CGEvent keystroke injection | Accessibility/Input-related permission possible |
| Apple Events / osascript | Automation permission, usage description |
| OSC/Bonjour/local network | Local Network privacy considerations |
| AUv3 | Code signing, extension validation |
| MCP stdio server | Relatively simple |
| MCP HTTP/WebSocket server | Local network/firewall considerations |

### Design implications
- Distribution requirements differ between running CLI only vs. including a menu bar app/helper.
- When using OSC/Bonjour, local network privacy testing is required.

---

## 15. Recommended MCP Architecture

```text
logic-pro-mcp
 ├─ MCP protocol layer
 ├─ Command planner
 ├─ State cache
 ├─ Providers
 │ ├─ CoreMIDIProvider
 │ │ ├─ virtual MIDI source
 │ │ ├─ virtual MIDI destination
 │ │ ├─ MCU/HUI encoder/decoder
 │ │ └─ simple CC/Note sender
 │ ├─ OSCProvider
 │ │ ├─ UDP IPv4 sender
 │ │ ├─ feedback listener
 │ │ └─ assignment profile
 │ ├─ AXProvider
 │ │ ├─ menu executor
 │ │ ├─ dialog handler
 │ │ ├─ window observer
 │ │ └─ visible state reader
 │ ├─ FileProvider
 │ │ ├─ MIDI writer
 │ │ ├─ audio/stem manager
 │ │ ├─ FCPXML/AAF helper
 │ │ └─ import/export orchestration
 │ └─ PluginBridgeProvider
 │   ├─ Scripter profile
 │   └─ optional AUv3 bridge
 └─ Logic profiles
   ├─ Logic 12.2 English AX map
   ├─ Logic 12.x key command map
   ├─ Controller assignment preset
   └─ MCU/HUI profile
```

### Provider priority examples

#### transport.play
1. MCU transport command
2. MIDI key-command assignment
3. AX menu/key command
4. CGEvent fallback

#### mixer.set_volume
1. MCU fader
2. OSC/controller assignment
3. MIDI CC assignment
4. AX fallback

#### project.bounce
1. AX menu/dialog automation
2. Key command + AX dialog
3. Unsupported

---

## 16. MCP Tool Design Examples

### Transport
- `logic.transport.play()`
- `logic.transport.stop()`
- `logic.transport.toggle_play()`
- `logic.transport.record()`
- `logic.transport.set_cycle(enabled: boolean)`
- `logic.transport.go_to_bar(bar: number)`

Implementation: MCU/HUI or key-command MIDI. Position input can be assisted by AX or key command dialog.

### Mixer
- `logic.mixer.set_volume(track: number | string, db: number)`
- `logic.mixer.set_pan(track: number | string, pan: number)`
- `logic.mixer.mute(track, enabled)`
- `logic.mixer.solo(track, enabled)`
- `logic.mixer.arm(track, enabled)`
- `logic.mixer.select_track(track)`
- `logic.mixer.bank(offset)`

Implementation: MCU preferred. Track name-based lookup requires `scribble strip feedback` or `AX visible track parsing`.

### Plugin / Smart Controls
- `logic.smart_control.set(name_or_index, value)`
- `logic.plugin.focused.set_parameter(index, value)`
- `logic.plugin.focused.next_parameter()`
- `logic.plugin.focused.bypass(enabled)`

Implementation: Controller Assignments / OSC / MCU plugin edit. Plugin insertion requires AX.

### Project I/O
- `logic.project.open(path)`
- `logic.project.import_midi(path)`
- `logic.project.import_audio(path)`
- `logic.project.export_aaf(path)`
- `logic.project.export_fcpxml(path)`
- `logic.project.bounce(path, format, range)`

Implementation: File open is possible via NSWorkspace/Apple Event. Import/export/bounce — AX is the practical path.

### Creative generation
- `logic.create_midi_region_from_prompt(prompt, track)`
- `logic.write_chord_progression(track, bars, style)`
- `logic.generate_drum_pattern(track, bars, genre)`

Implementation: MCP generates a MIDI file and imports it into Logic, or uses Scripter/AU bridge.

---

## 17. Paths to Avoid

### 1) Direct modification of `.logicx` internal `ProjectData`
- Not a public format
- Fragile against version upgrades
- High risk of data corruption

### 2) Going all-in on the Logic Remote protocol
- Not a public API
- High maintenance risk

### 3) Implementing the entire MCP using only pure AX/keyboard automation
- Fast for prototyping
- But brittle against language settings, window layout, Logic version, and modal state
- AX must remain a supplementary tool only

### 4) Over-relying on AppleScript/JXA
- Logic has a weak implementation of this path
- Limiting to launch/open/activate is the correct scope

---

## 18. Recommended Implementation Order

### Phase 1: CoreMIDI virtual port + basic transport
- Create virtual MIDI source/destination
- Provide Logic Controller Assignments preset
- `play / stop / record / cycle / metronome / count-in`

### Phase 2: MCU emulation
- Register virtual Mackie Control
- Establish fader / pan / mute / solo / select / bank / display feedback
- By this point, MCP can approximately estimate session state

### Phase 3: AXProvider
- Bounce / export / import / preferences / project settings
- Modal error handling
- Implement based on AX menu item / form field rather than coordinate clicks

### Phase 4: FileProvider
- MIDI generation/import
- Audio stem management
- FCPXML / AAF export/import

### Phase 5: Scripter or AU Bridge
- Music generation
- Real-time MIDI processing
- In-project intelligence based on host timing

---

## 19. Repo-Specific Implications

Based on the past operational history of this repo, the areas requiring particular care going forward are:

### A. Verification reads are harder than writes
Even when transport or track/mixer commands execute, if the readback is stale, MCP will report a false completion. Therefore:
- Separate command success from state verification
- Keep verification timeout and stale cache detection as distinct states
- Treat `attempted but unverified` as a formal result type

### B. `project.open` class operations must strongly guard against false positives
- Do not trust only a success response — cross-verify against actual front document / document count / visible window
- Separate the AppleScript model, AX window model, and internal cache

### C. UI/window corruption handling is required
- When the Logic runtime becomes inconsistent, mismatches can occur — e.g., AX reports 0 windows while AppleScript reports 1 document.
- Therefore, health checks must be multi-layered:
  - Process alive
  - App frontmost
  - Document count
  - Front document path
  - AX focused window
  - Main window bounds
  - MCU connected / MIDI device registered
  - Modal present or not

---

## 20. Final Conclusion

There is no "correct API" for building a Logic Pro MCP.

However, the combination closest to a realistic answer is clear.

### Final recommendations
1. `CoreMIDI virtual device`
2. `Mackie Control / HUI emulation`
3. `Logic Controller Assignments + key commands`
4. `OSC Message Paths where useful`
5. `AXUIElement for menus/dialogs/visible state`
6. `MIDI / AAF / FCPXML for file-level exchange`
7. `Scripter / AU for in-project intelligence`

### Default backend recommendations
- **Primary control**: MCU over CoreMIDI
- **Secondary control**: MIDI key-command assignments
- **Parameter layer**: OSC or Controller Assignments
- **UI fallback**: AXUIElement
- **Content layer**: MIDI / FCPXML / AAF + optional Scripter/AU bridge
- **Avoid**: private Logic Remote protocol, direct `.logicx` mutation

This direction is comparatively resilient to Logic updates and maps most cleanly to MCP tool abstraction.

---

## 21. Reference Basis

### Local verification
- `/Applications/Logic Pro.app`
- `/Users/isaac/Documents/Logic/LoFi-MCP-Demo.logicx`
- AppleScript/Info.plist/URL scheme/package structure confirmed

### Project operational notes
- `memory/2026-04-08.md`
- `memory/2026-04-09.md`
- `memory/2026-04-10.md`
- `memory/2026-04-12.md`

### Public documentation
- Logic Pro User Guide for Mac
- Audio MIDI Setup / MIDI devices
- Apple Core MIDI documentation
- Apple Audio Unit v3 Plug-Ins documentation
- Apple Accessibility / AXUIElement documentation

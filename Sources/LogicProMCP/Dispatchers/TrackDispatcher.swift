import Foundation
import MCP

struct TrackDispatcher {
    static let tool = Tool(
        name: "logic_tracks",
        description: "Track actions in Logic Pro. Commands: select, create_audio, create_instrument, create_drummer, create_external_midi, delete, duplicate, rename, mute, solo, arm, arm_only, record_sequence, set_automation, set_instrument, list_library, scan_library, resolve_path, scan_plugin_presets. Params: select -> { index: Int } or { name: String }; rename/mute/solo/arm/arm_only/set_automation/set_instrument ALL require explicit { index: Int (≥0) }; mute/solo/arm -> also { enabled: Bool }; arm_only disarms all others + arms target, returns error on partial disarm failure; record_sequence -> { bar?: Int (default 1), notes: \"pitch,offsetMs,durMs[,vel[,ch]];...\" (BREAKING since v3.1.6: optional `ch` field is 1-based, range 1..16 — pre-v3.1.6 was 0-based; whole-parse-fail on any invalid segment; SMF end <= 3,600,000 ms), tempo?: Float } v3.0.8 SMF-import path: generates a Standard MIDI File server-side, forces playhead to bar 1, imports via AX menu — byte-exact timing, creates a new track each call. v3.0.8 REMOVED the internal instrument auto-load: response always carries `\"instrument\":\"not-attempted\"`. The new track keeps Logic's default Software Instrument (Studio Grand piano on a fresh project); callers that want a specific patch must follow up with an explicit `set_instrument` AFTER ensuring the intended track is selected. The legacy `instrument_path` param is accepted for wire compat but ignored (surfaces as `\"ignored:<path>\"` in the response) — see CHANGELOG v3.0.8 for why the inline auto-load was unsafe (could load the wrong track's patch, corrupting a pre-existing track); create_* -> {}; delete/duplicate -> { index: Int }; set_automation -> { mode: read|write|touch|latch|trim|off }; set_instrument -> { path: String } or { category: String, preset: String } — path mode preferred; scan_library -> { mode?: \"ax\"|\"disk\"|\"both\" } (default ax — live Library Panel; disk reads ~/Music/Logic Pro Library.bundle for 5,400+ leaves with Panel-taxonomy remap; both returns diff summary); resolve_path -> { path: String } cache-backed read-only; scan_plugin_presets -> { submenuOpenDelayMs?: Int }.",
        inputSchema: commandParamsToolSchema(commandDescription: "Track command to execute")
    )

    static func handle(
        command: String,
        params: [String: Value],
        router: ChannelRouter,
        cache: StateCache
    ) async -> CallTool.Result {
        switch command {
        case "select":
            // Prefer index (accepts int/double/string), else match by name. If
            // `index` is supplied but not a valid non-negative integer, fail
            // closed — silently falling back to track 0 on a malformed
            // request would corrupt the wrong track.
            if params["index"] != nil || params["track"] != nil {
                guard let index = intParamOrNil(params, "index", "track") else {
                    return toolTextResult(
                        "select 'index' must be a non-negative integer (non-numeric or missing value rejected)",
                        isError: true
                    )
                }
                guard index >= 0 else {
                    return toolTextResult(
                        "select 'index' must be ≥ 0 (got \(index)) — Logic doesn't have negative track indices",
                        isError: true
                    )
                }
                let result = await router.route(
                    operation: "track.select",
                    params: ["index": String(index)]
                )
                return toolTextResult(result)
            }
            let name = stringParam(params, "name")
            if !name.isEmpty {
                let tracks = await cache.getTracks()
                if let track = tracks.first(where: { $0.name.localizedCaseInsensitiveContains(name) }) {
                    let result = await router.route(
                        operation: "track.select",
                        params: ["index": String(track.id)]
                    )
                    return toolTextResult(result)
                }
                return toolTextResult("No track found matching '\(name)'", isError: true)
            }
            return toolTextResult("select requires 'index' or 'name' param", isError: true)

        case "create_audio":
            let result = await router.route(operation: "track.create_audio")
            return toolTextResult(result)

        case "create_instrument":
            let result = await router.route(operation: "track.create_instrument")
            return toolTextResult(result)

        case "create_drummer":
            let result = await router.route(operation: "track.create_drummer")
            return toolTextResult(result)

        case "create_external_midi":
            let result = await router.route(operation: "track.create_external_midi")
            return toolTextResult(result)

        case "delete":
            guard let index = intParamOrNil(params, "index", "track"), index >= 0 else {
                return toolTextResult("delete requires explicit 'index' (Int ≥ 0)", isError: true)
            }
            let selectResult = await router.route(
                operation: "track.select",
                params: ["index": String(index)]
            )
            guard selectResult.isSuccess else {
                return toolTextResult(selectResult.message, isError: true)
            }
            // v3.1.2 P1-5 — `track.select` can return State B (`verified:false`,
            // e.g. `reason:"retry_exhausted"` or `"readback_mismatch"`) while
            // the outer ChannelResult is still `.success`. State B means
            // "the AX write was issued but the read-back could not confirm
            // selection landed on the requested track". Following State B
            // with `track.delete` is unsafe: the previously-selected track
            // (whatever it was) gets deleted instead of the requested target,
            // an irrecoverable data-loss scenario. Refuse the delete and
            // require the caller to re-issue selection (or accept that the
            // selection is uncertain and abort).
            guard let data = selectResult.message.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let verified = json["verified"] as? Bool, verified == true else {
                return toolTextResult(
                    "track.delete refused: track \(index) selection unverified (State B). Cannot safely delete unverified target — re-select or fix Logic Pro AX state and retry. select_response=\(selectResult.message)",
                    isError: true
                )
            }
            let result = await router.route(operation: "track.delete")
            return toolTextResult(result)

        case "duplicate":
            guard let index = intParamOrNil(params, "index", "track"), index >= 0 else {
                return toolTextResult("duplicate requires explicit 'index' (Int ≥ 0)", isError: true)
            }
            let selectResult = await router.route(
                operation: "track.select",
                params: ["index": String(index)]
            )
            guard selectResult.isSuccess else {
                return toolTextResult(selectResult.message, isError: true)
            }
            // RB-1.c (2026-05-08 enterprise review): mirror the State-B
            // refusal gate that `delete` already enforces. `track.select`
            // can return State B (`verified:false`, e.g. `readback_mismatch`
            // or `retry_exhausted`) while the outer ChannelResult is still
            // `.success`. Following State B with `track.duplicate` would
            // duplicate whatever track is currently selected (which can
            // differ from the requested index), creating a phantom track
            // and confusing the caller's mental model. Refuse and require
            // the caller to re-issue selection.
            guard let data = selectResult.message.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let verified = json["verified"] as? Bool, verified == true else {
                return toolTextResult(
                    "track.duplicate refused: track \(index) selection unverified (State B). Cannot safely duplicate unverified target — re-select or fix Logic Pro AX state and retry. select_response=\(selectResult.message)",
                    isError: true
                )
            }
            let result = await router.route(operation: "track.duplicate")
            return toolTextResult(result)

        case "rename":
            guard let index = intParamOrNil(params, "index", "track"), index >= 0 else {
                return toolTextResult("rename requires explicit 'index' (Int ≥ 0)", isError: true)
            }
            let name = stringParam(params, "name")
            guard !name.isEmpty else {
                return toolTextResult("rename requires 'name' parameter", isError: true)
            }
            let result = await router.route(
                operation: "track.rename",
                params: ["index": String(index), "name": name]
            )
            return toolTextResult(result)

        case "mute":
            guard let index = intParamOrNil(params, "index", "track"), index >= 0 else {
                return toolTextResult("mute requires explicit 'index' (Int ≥ 0)", isError: true)
            }
            let enabled: Bool
            if params["enabled"] != nil {
                guard let parsed = boolParamOrNil(params, "enabled") else {
                    return MIDIDispatcher.invalidParamsResult(
                        hint: "mute 'enabled' must be boolean true/false"
                    )
                }
                enabled = parsed
            } else {
                enabled = true
            }
            let result = await router.route(
                operation: "track.set_mute",
                params: ["index": String(index), "enabled": String(enabled)]
            )
            return toolTextResult(result)

        case "solo":
            guard let index = intParamOrNil(params, "index", "track"), index >= 0 else {
                return toolTextResult("solo requires explicit 'index' (Int ≥ 0)", isError: true)
            }
            let enabled: Bool
            if params["enabled"] != nil {
                guard let parsed = boolParamOrNil(params, "enabled") else {
                    return MIDIDispatcher.invalidParamsResult(
                        hint: "solo 'enabled' must be boolean true/false"
                    )
                }
                enabled = parsed
            } else {
                enabled = true
            }
            let result = await router.route(
                operation: "track.set_solo",
                params: ["index": String(index), "enabled": String(enabled)]
            )
            return toolTextResult(result)

        case "arm":
            guard let index = intParamOrNil(params, "index", "track"), index >= 0 else {
                return toolTextResult("arm requires explicit 'index' (Int ≥ 0)", isError: true)
            }
            let enabled: Bool
            if params["enabled"] != nil {
                guard let parsed = boolParamOrNil(params, "enabled") else {
                    return MIDIDispatcher.invalidParamsResult(
                        hint: "arm 'enabled' must be boolean true/false"
                    )
                }
                enabled = parsed
            } else {
                enabled = true
            }
            let result = await router.route(
                operation: "track.set_arm",
                params: ["index": String(index), "enabled": String(enabled)]
            )
            return toolTextResult(result)

        case "record_sequence":
            return await handleRecordSequenceSMF(params: params, router: router, cache: cache)

        case "arm_only":
            guard let index = intParamOrNil(params, "index", "track"), index >= 0 else {
                return toolTextResult("arm_only requires explicit 'index' (Int ≥ 0)", isError: true)
            }
            let tracks = await cache.getTracks()
            var disarmed: [Int] = []
            var failedDisarm: [Int] = []
            for t in tracks where t.id != index && t.isArmed {
                let r = await router.route(
                    operation: "track.set_arm",
                    params: ["index": String(t.id), "enabled": "false"]
                )
                if r.isSuccess { disarmed.append(t.id) } else { failedDisarm.append(t.id) }
            }
            let armResult = await router.route(
                operation: "track.set_arm",
                params: ["index": String(index), "enabled": "true"]
            )
            // If the primary arm action failed, return an explicit error instead
            // of a structured success payload. Partial-disarm visibility still
            // available in the error detail.
            let detail = armResult.message.replacingOccurrences(of: "\"", with: "\\\"")
            guard armResult.isSuccess else {
                return toolTextResult(
                    "arm_only failed: target arm rejected — \(armResult.message); disarmed=\(disarmed) failedDisarm=\(failedDisarm)",
                    isError: true
                )
            }
            // Report partial disarm failures explicitly — the target arm
            // succeeded, but some other tracks may still be armed.
            if !failedDisarm.isEmpty {
                return toolTextResult(
                    "arm_only partial: target \(index) armed, but these tracks failed to disarm: \(failedDisarm) (disarmed: \(disarmed))",
                    isError: true
                )
            }
            return toolTextResult(.success(
                "{\"armed\":\(index),\"armedSuccess\":true,\"disarmed\":\(disarmed),\"failedDisarm\":[],\"detail\":\"\(detail)\"}"
            ))

        case "set_color":
            return toolTextResult("set_color is not exposed in the production MCP contract", isError: true)

        case "set_automation":
            guard let index = intParamOrNil(params, "index", "track"), index >= 0 else {
                return toolTextResult("set_automation requires explicit 'index' (Int ≥ 0)", isError: true)
            }
            let mode = stringParam(params, "mode", default: "read")
            let validModes = ["read", "write", "touch", "latch", "trim", "off"]
            guard validModes.contains(mode) else {
                return toolTextResult(
                    "set_automation 'mode' must be one of \(validModes.joined(separator: ", ")) (got '\(mode)')",
                    isError: true
                )
            }
            let result = await router.route(
                operation: "track.set_automation",
                params: ["index": String(index), "mode": mode]
            )
            return toolTextResult(result)

        case "set_instrument":
            guard let index = intParamOrNil(params, "index"), index >= 0 else {
                return toolTextResult("set_instrument requires explicit 'index' (Int ≥ 0)", isError: true)
            }
            let category = stringParam(params, "category")
            let preset = stringParam(params, "preset")
            let path = stringParam(params, "path")
            guard !path.isEmpty || (!category.isEmpty && !preset.isEmpty) else {
                return toolTextResult(
                    "set_instrument requires 'path' or both 'category' + 'preset'",
                    isError: true
                )
            }
            var routeParams: [String: String] = ["index": String(index)]
            if !path.isEmpty { routeParams["path"] = path }
            if !category.isEmpty { routeParams["category"] = category }
            if !preset.isEmpty { routeParams["preset"] = preset }
            let result = await router.route(
                operation: "track.set_instrument",
                params: routeParams
            )
            return toolTextResult(result)

        case "resolve_path":
            let path = stringParam(params, "path")
            if path.isEmpty {
                return toolTextResult("Missing 'path' parameter", isError: true)
            }
            let result = await router.route(
                operation: "library.resolve_path",
                params: ["path": path]
            )
            return toolTextResult(result)

        case "list_library", "library":
            let result = await router.route(operation: "library.list")
            return toolTextResult(result)

        case "scan_library":
            // v3.0.7: forward `mode` param (ax|disk|both) to the scan handler.
            // Previously dropped on the floor — v3.0.6 mode routing was dead.
            var scanParams: [String: String] = [:]
            let mode = stringParam(params, "mode")
            if !mode.isEmpty {
                guard ["ax", "disk", "both"].contains(mode) else {
                    return MIDIDispatcher.invalidParamsResult(
                        hint: "scan_library 'mode' must be one of: ax, disk, both"
                    )
                }
                scanParams["mode"] = mode
            }
            let result = await router.route(
                operation: "library.scan_all",
                params: scanParams
            )
            return toolTextResult(result)

        case "scan_plugin_presets":
            // F2 minimal — scans the currently-focused plugin window's Setting menu.
            let settleMs: Int
            if params["submenuOpenDelayMs"] != nil {
                guard let parsed = intParamOrNil(params, "submenuOpenDelayMs"),
                      (0...5000).contains(parsed) else {
                    return MIDIDispatcher.invalidParamsResult(
                        hint: "scan_plugin_presets 'submenuOpenDelayMs' must be an integer in 0..5000"
                    )
                }
                settleMs = parsed
            } else {
                settleMs = 250
            }
            let result = await router.route(
                operation: "plugin.scan_presets",
                params: ["submenuOpenDelayMs": String(settleMs)]
            )
            return toolTextResult(result)

        default:
            return toolTextResult(
                "Unknown track command: \(command). Available: select, create_audio, create_instrument, create_drummer, create_external_midi, delete, duplicate, rename, mute, solo, arm, arm_only, record_sequence, set_automation, set_instrument, list_library, scan_library, resolve_path, scan_plugin_presets",
                isError: true
            )
        }
    }

    // MARK: - record_sequence SMF-import implementation

    /// Generate a Standard MIDI File from the notes spec, write to /tmp/LogicProMCP/,
    /// then import into the current project via AX menu navigation. Logic always
    /// creates a NEW MIDI track for the imported content (verified OQ-3).
    static func handleRecordSequenceSMF(
        params: [String: MCP.Value],
        router: ChannelRouter,
        cache: StateCache
    ) async -> CallTool.Result {
        // T5 — record_sequence does not support `port` (no keycmd alternative
        // for SMF-import + AX menu navigation). Reject up-front rather than
        // silently dropping the argument, so a caller who mistakenly thinks
        // `port:"keycmd"` would route this op gets an actionable hint instead
        // of a misleading success at the wrong transport.
        if params["port"] != nil {
            return MIDIDispatcher.invalidParamsResult(
                hint: "port parameter not supported for record_sequence"
            )
        }
        let bar: Int
        if params["bar"] != nil {
            guard let parsed = intParamOrNil(params, "bar"),
                  (1...9999).contains(parsed) else {
                return MIDIDispatcher.invalidParamsResult(
                    hint: "record_sequence 'bar' must be an integer in 1..9999"
                )
            }
            bar = parsed
        } else {
            bar = 1
        }
        let notes: String
        if let rawNotes = params["notes"] {
            guard let parsed = rawNotes.stringValue, !parsed.isEmpty else {
                return MIDIDispatcher.invalidParamsResult(
                    hint: "record_sequence requires 'notes' as a non-empty string"
                )
            }
            notes = parsed
        } else {
            return MIDIDispatcher.invalidParamsResult(
                hint: "record_sequence requires 'notes' (semicolon-separated 'pitch,offsetMs,durMs[,vel[,ch]]')"
            )
        }
        let requestedTempo: Double?
        if params["tempo"] != nil {
            guard let parsed = doubleParamOrNil(params, "tempo"), (5.0...999.0).contains(parsed) else {
                return MIDIDispatcher.invalidParamsResult(
                    hint: "record_sequence 'tempo' must be numeric in 5..999"
                )
            }
            requestedTempo = parsed
        } else {
            requestedTempo = nil
        }
        guard await cache.getHasDocument() else {
            return toolTextResult("record_sequence: No project open", isError: true)
        }

        let project = await cache.getProject()
        let cacheTempo = project.tempo > 0 ? project.tempo : 120.0
        let tempo = requestedTempo ?? cacheTempo
        // T3 — strict whole-parse-fail. The previous silent-skip parser left
        // callers unable to distinguish "user typed garbage" from "all
        // segments happened to be invalid", so the error wording was vague
        // ("could not parse any valid notes"). The new Result API surfaces
        // the specific failure (channel out of range, malformed segment,
        // etc.) so the LLM agent can self-correct on the next call.
        let events: [SMFWriter.NoteEvent]
        switch parseNotesToSMFEvents(notes: notes, tempo: tempo) {
        case .success(let parsed):
            events = parsed
        case .failure(let error):
            return toolTextResult(
                "record_sequence: invalid 'notes' — \(error.message)",
                isError: true
            )
        }
        guard !events.isEmpty else {
            return toolTextResult(
                "record_sequence: 'notes' parsed to zero events (input: '\(notes)')",
                isError: true
            )
        }
        // v3.1.2 P1-4 — enforce the 1024-note SMF-import upper bound that
        // `NoteSequenceParser`'s docstring already advertises. Without this
        // guard, a malformed (or adversarial) caller could hand SMFWriter an
        // arbitrarily large event list, which would produce an oversize
        // .mid file and slow Logic's MIDI File Import dialog enough to
        // appear hung. The 1024 limit matches the documented upper bound and
        // leaves a comfortable margin under SMFWriter's tick-encoding bounds.
        guard events.count <= 1024 else {
            return toolTextResult(
                "record_sequence: too many notes (\(events.count) > 1024 max for SMF import)",
                isError: true
            )
        }

        let tempDir = "/tmp/LogicProMCP"
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        let path = "\(tempDir)/\(UUID().uuidString).mid"
        defer {
            try? FileManager.default.removeItem(atPath: path)
        }

        // Logic's MIDI File import strips leading empty delta before the first
        // channel event (region gets placed at bar 1 regardless of SMF offset).
        // SMFWriter counters this by emitting a padding CC#110 @ tick 0 when
        // bar > 1, so the first note lands at the requested bar inside a
        // region that spans bar 1 → bar+length. The region is cosmetically
        // longer than the notes, but note timing is exact with zero drift.
        do {
            let data = try SMFWriter.generate(
                events: events,
                bar: bar,
                tempo: tempo,
                timeSignature: (4, 4)
            )
            try data.write(to: URL(fileURLWithPath: path))
        } catch {
            return toolTextResult("record_sequence: SMF generation failed: \(error)", isError: true)
        }

        // Logic Pro's MIDI File Import anchors the imported region to the
        // CURRENT playhead position. SMF Strategy D encodes the bar offset
        // inside the file (relative to tick 0), so the playhead must be at
        // bar 1 before import — otherwise notes land at playhead + offset,
        // not at the requested bar. A silent failure here would produce a
        // success response with content at the wrong position, so the goto
        // is a hard precondition: hasDocument is already true (guarded
        // above), so the goto-dialog is enabled on any non-empty project,
        // and on an empty project the playhead is already at bar 1 and the
        // slider fallback succeeds trivially.
        let gotoResult = await router.route(
            operation: "transport.goto_position",
            params: ["bar": "1"]
        )
        guard gotoResult.isSuccess else {
            return toolTextResult(
                "record_sequence failed to reset playhead to bar 1 (required for accurate import): \(gotoResult.message)",
                isError: true
            )
        }

        // v3.1.2 (P0-2) — verify track creation against LIVE AX, not the
        // 3-second StatePoller cache. The previous cache-poll loop (2s
        // window, 100ms granularity) was strictly shorter than the poller
        // interval (3s, see ServerConfig.statePollingIntervalNs), so on a
        // healthy import the track count delta would not propagate to
        // `cache.getTracks()` until *after* the verification deadline,
        // false-failing every successful run on first call. Live-witnessed
        // 3× in production sessions.
        //
        // The downstream import handler (AccessibilityChannel
        // `defaultImportMIDIFile`) already validates the count delta against
        // `AXLogicProElements.allTrackHeaders()` before returning success,
        // so an `importResult.isSuccess` is itself a proof of new-track
        // creation. We re-read the same live AX surface here only to
        // discover the track index for the response payload — and we still
        // ask the poller to refresh so the next cache read is fresh too.
        let tracksBefore = AXLogicProElements.allTrackHeaders().count
        let importResult = await router.route(
            operation: "midi.import_file",
            params: ["path": path]
        )
        guard importResult.isSuccess else {
            return toolTextResult(
                "record_sequence failed at midi.import_file: \(importResult.message)",
                isError: true
            )
        }

        // Re-read live AX to confirm the new track index. Import handler has
        // already verified the delta, so we expect tracksAfter > tracksBefore
        // immediately; the small retry loop is purely defensive against AX
        // tree settle latency on slow machines (≤500ms total).
        var tracksAfter = AXLogicProElements.allTrackHeaders().count
        for _ in 0..<5 {
            if tracksAfter > tracksBefore { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
            tracksAfter = AXLogicProElements.allTrackHeaders().count
        }
        guard tracksAfter > tracksBefore else {
            return toolTextResult(
                "record_sequence: import handler reported success but live AX still shows \(tracksBefore) tracks (no delta within 500ms). Check Logic Pro UI and retry.",
                isError: true
            )
        }

        let createdTrack = tracksAfter - 1

        // v3.0.8 — instrument auto-load has been REMOVED from record_sequence.
        //
        // Prior versions (v3.0.2 – v3.0.7) auto-routed `track.set_instrument`
        // on the just-created track, defaulted `instrument_path` to
        // `"Synthesizer/Bass"`, and reported `"instrument":"loaded:..."` based
        // on `setResult.isSuccess`. Live testing on v3.0.7 + v3.0.8-draft
        // revealed two compounding bugs that made that path untrustworthy:
        //
        //   1. `LibraryAccessor.selectPath`'s AXPress on the preset leaf
        //      returns `.success` when the AX action is *delivered*, not when
        //      Logic's handler actually swaps the channel-strip instrument.
        //      `selectCategory` unconditionally returns `true` once the
        //      AXStaticText element is found, whether or not the AX write
        //      committed.
        //   2. `AXLogicProElements.selectTrackViaAX(at:)` is silently unable
        //      to change selection on a freshly-created track header on the
        //      first run-loop tick after SMF import. AXPress, AXSelected,
        //      child AXPress, and coord-click ALL get dropped; the header is
        //      visible in the AX tree and `findTrackHeader` resolves it, but
        //      selection never moves off the previously-selected track. The
        //      downstream `selectPath` then loads the preset onto whichever
        //      track was already selected — which can CORRUPT a pre-existing
        //      track's patch. Observed live: `record_sequence` with
        //      `instrument_path: "Electronic Drums/Brooklyn Borough"` on a
        //      project with a pre-existing `Deluxe Classic` (Electric Piano)
        //      track silently replaced `Deluxe Classic`'s patch with the
        //      Brooklyn Borough drum kit, while the new MIDI-imported track
        //      kept its default `Studio Grand` piano.
        //
        // v3.0.9 note — the `selectTrackViaAX` primitive itself is now fixed
        // (switched to AXSelectedChildren on the parent "Tracks header" group,
        // which is what Library preset selection already used). Callers of
        // `track.set_instrument { index: N }` now consistently target track N.
        // The record_sequence internal auto-load is STILL removed, however:
        // bundling two separate live Logic ops inside one dispatcher call
        // creates ordering dependencies that are hard to reason about, and
        // Isaac's policy on this ("decouple") stands. Callers who want a
        // specific patch after `record_sequence` should call `track.select`
        // + `track.set_instrument` explicitly on the returned track index.
        let instrumentPath = stringParam(params, "instrument_path", "instrument")
        let instrumentStatus: String
        if instrumentPath.isEmpty {
            instrumentStatus = "not-attempted"
        } else {
            instrumentStatus = "ignored:\(instrumentPath) (v3.0.8: internal auto-load removed to prevent corrupting a pre-existing track — call set_instrument explicitly; see CHANGELOG v3.0.8 for the selectTrackViaAX limitation on fresh SMF-created tracks)"
        }

        return toolTextResult(.success(
            "{\"recorded_to_track\":\(createdTrack),\"created_track\":\(createdTrack),\"bar\":\(bar),\"note_count\":\(events.count),\"method\":\"smf_import\",\"instrument\":\"\(escapeJSONString(instrumentStatus))\"}"
        ))
    }

    /// Minimal JSON string escape for the one field we embed verbatim. The
    /// `instrumentStatus` text can legitimately contain `"`, `\\`, or
    /// newlines (when it carries a forwarded error message), so we escape
    /// rather than trust the source.
    private static func escapeJSONString(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if ch.asciiValue.map({ $0 < 0x20 }) == true {
                    out += String(format: "\\u%04x", ch.asciiValue!)
                } else {
                    out.append(ch)
                }
            }
        }
        return out
    }

    private static func parseNotesToSMFEvents(
        notes: String,
        tempo: Double
    ) -> Result<[SMFWriter.NoteEvent], RecordSequenceNoteValidationError> {
        switch NoteSequenceParser.parse(notes) {
        case .failure(let error):
            return .failure(RecordSequenceNoteValidationError(message: error.hint))
        case .success(let parsed):
            if let violation = NoteSequenceParser.smfTimingViolation(in: parsed) {
                return .failure(RecordSequenceNoteValidationError(message: violation))
            }
            return .success(parsed.map { note in
                let ticks = SMFWriter.msToTicks(
                    offsetMs: note.offsetMs,
                    durationMs: note.durationMs,
                    tempo: tempo
                )
                return SMFWriter.NoteEvent(
                    pitch: note.pitch,
                    offsetTicks: ticks.offsetTicks,
                    durationTicks: ticks.durationTicks,
                    velocity: note.velocity,
                    channel: note.channel
                )
            })
        }
    }

    private struct RecordSequenceNoteValidationError: Error {
        let message: String
    }

}

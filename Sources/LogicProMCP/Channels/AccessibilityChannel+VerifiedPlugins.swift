import ApplicationServices
import Foundation

/// Verified-plugin surface (`logic_plugins.*`) channel implementation.
///
/// T3 scope (requirements §8 / development board T3):
///   - `plugin.get_inventory` — fully deterministic, drift-safe inventory built
///     from the T2 `audioPluginInsertSlots` enumerator (R3, AC2/AC12/AC22).
///   - `plugin.set_param_verified` — R6 precedence steps 1-5 only. The live
///     write path (steps 6+) belongs to T4/T5 and requires T0 evidence; Gain's
///     capability preflight (step 5) returns State C `unsupported_param_readback`
///     today, so steps 6+ are unreachable by design (AC10).
///   - `plugin.insert_verified` — live validation gates (schema/mode/path/
///     identity/inventory-complete/slot-empty/slot-is-first-free) followed by the
///     live "Mix > Search and Add Plug-in" insert (R12 breakthrough). The
///     Mix-menu search dialog mounts into the first empty audio-effect slot, and
///     a post-insert `get_inventory` readback is the SOLE State A precondition —
///     State A is reachable only when the requested plugin is observed at the
///     requested slot, so a false verified insert is structurally impossible
///     (T6). Any other outcome fails closed with a terminal HC v2 State C.
///
/// NOTE: `set_param_verified` is the only live AX parameter write/readback (State
/// A) path; `insert_verified` reaches State A solely through its post-insert
/// inventory readback. Every uncertain or mismatched outcome fails closed.
extension AccessibilityChannel {

    // MARK: - get_inventory (R3, AC2/AC12/AC22)

    /// Build the `plugins[]` array for one strip from its drift-safe slot
    /// enumeration. Pure + deterministic so it can be unit-tested against a
    /// strip element without a full mixer fixture.
    ///
    /// Per AC22 EVERY item carries `insert`/`read_status`/`occupied`/`name`/
    /// `plugin_id`/`bypassed` — value-less fields are explicit `NSNull`, never
    /// omitted, so a caller can tell "field absent" from "value unknown".
    static func pluginInventoryItems(
        for slots: [AXLogicProElements.PluginInsertSlot]
    ) -> (items: [[String: Any]], complete: Bool) {
        var items: [[String: Any]] = []
        var complete = true
        for slot in slots {
            var item: [String: Any] = [
                "insert": slot.index,
                "read_status": slot.readStatus.rawValue,
                "occupied": slot.occupied,
            ]
            switch slot.readStatus {
            case .empty:
                item["name"] = NSNull()
                item["plugin_id"] = NSNull()
                item["bypassed"] = NSNull()
            case .occupiedUnreadable:
                complete = false
                item["name"] = NSNull()
                item["plugin_id"] = NSNull()
                item["bypassed"] = NSNull()
            case .occupiedReadable:
                let name = slot.name
                item["name"] = name ?? NSNull()
                // canonical match against the allowlist, else null (an occupied
                // readable slot whose name is not an allowlisted stock plugin is
                // a real slot but not a verified-write target — §5.2).
                item["plugin_id"] = name.flatMap(VerifiedPluginCatalog.pluginID(forObservedName:)) ?? NSNull()
                item["bypassed"] = slot.isBypassed ?? NSNull()
            }
            items.append(item)
        }
        return (items, complete)
    }

    /// `plugin.get_inventory` channel entry. Non-mutating: never carries
    /// `write_source`/`verify_source`. Returns a `complete:true|false` snapshot
    /// (HC-v2-adjacent inventory shape) when the strip can be enumerated, or
    /// State B `readback_unavailable` when the AX insert subtree cannot be read
    /// at all (AC2).
    static func defaultGetPluginInventory(
        params: [String: String],
        runtime: AXLogicProElements.Runtime = .production
    ) -> ChannelResult {
        let operation = "logic_plugins.get_inventory"
        guard let trackRaw = params["track"] ?? params["track_index"] ?? params["index"],
              let track = Int(trackRaw), track >= 0 else {
            return .error(HonestContract.encodeV2StateC(
                error: .invalidParams,
                extras: [
                    "operation": operation,
                    "what_was_attempted": "read insert chain inventory",
                    "what_was_observed": "missing or invalid 'track' (expected Int >= 0)",
                    "safe_to_retry": false,
                ]
            ))
        }

        let fetchedAt = ISO8601DateFormatter.cacheFormatter.string(from: Date())

        // The AX insert subtree is unreadable when the mixer or the requested
        // strip cannot be located — there is nothing to enumerate, so this is
        // State B `readback_unavailable` rather than a fabricated empty chain.
        guard let mixer = AXLogicProElements.getMixerArea(runtime: runtime) else {
            return .success(HonestContract.encodeV2StateB(
                reason: .readbackUnavailable,
                extras: [
                    "operation": operation,
                    "track": track,
                    "plugins_source": "ax",
                    "plugins_fetched_at": fetchedAt,
                    "plugins_unknown_reason": "ax_subtree_unreadable",
                    "what_was_attempted": "read insert chain inventory for track \(track)",
                    "what_was_observed": "mixer area was not locatable in the AX tree",
                    "safe_to_retry": true,
                ]
            ))
        }
        let strips = AXLogicProElements.mixerChannelStrips(in: mixer, runtime: runtime.ax)
        guard track < strips.count else {
            return .success(HonestContract.encodeV2StateB(
                reason: .readbackUnavailable,
                extras: [
                    "operation": operation,
                    "track": track,
                    "plugins_source": "ax",
                    "plugins_fetched_at": fetchedAt,
                    "plugins_unknown_reason": "ax_subtree_unreadable",
                    "what_was_attempted": "read insert chain inventory for track \(track)",
                    "what_was_observed": "track index \(track) is not present in the visible mixer (\(strips.count) strips)",
                    "safe_to_retry": true,
                ]
            ))
        }

        let slots = AXLogicProElements.audioPluginInsertSlots(in: strips[track], runtime: runtime.ax)
        let built = pluginInventoryItems(for: slots)

        return .success(HonestContract.jsonString([
            "operation": operation,
            "track": track,
            "plugins_source": "ax",
            "plugins_fetched_at": fetchedAt,
            "plugins_unknown_reason": NSNull(),
            "complete": built.complete,
            "plugins": built.items,
        ]))
    }

    // MARK: - Shared validation inputs

    /// Live front-document path provider for the project-identity gate. Defaults
    /// to the AppleScript probe; tests inject a deterministic value so the gate
    /// can be exercised without a running Logic Pro.
    typealias FrontDocumentPathProvider = @Sendable () async -> String?

    static let liveFrontDocumentPath: FrontDocumentPathProvider = {
        await AppleScriptChannel.currentDocumentPath()
    }

    /// Attempt to OPEN the plugin window for `(trackName, axDescription)` when it
    /// is not already open (R6 step 8b), returning the window element once it
    /// exposes the matching slider, or nil when no window could be opened.
    /// Injected so tests can deterministically drive the "must open" branch.
    ///
    /// Production default: returns nil. Opening a stock-effect plugin window via
    /// the mixer is empirically brittle (T0 spike §제약 4 — the mixer virtualises
    /// channel strips, so the insert double-click cannot be driven reliably from
    /// AX). Until that path is hardened (a separate ticket), the verified write
    /// only proceeds against an ALREADY-OPEN plugin window; otherwise it fails
    /// closed with `window_open_failed`. This keeps the production envelope
    /// honest rather than fabricating a write against a window that was never
    /// confirmed open.
    typealias PluginWindowOpener = @Sendable (_ trackName: String, _ axDescription: String) async -> AXUIElementSendable?

    static let liveNoOpPluginWindowOpener: PluginWindowOpener = { _, _ in nil }

    /// Steps 2-3 of the R6 precedence shared by both mutating verified ops:
    /// mode validation then the project path gate. Returns a State C envelope to
    /// short-circuit on failure, or nil to continue. `extras` carries the
    /// pre-resolution `target_identity` fields the caller already knows.
    private static func verifiedModeAndPathGate(
        operation: String,
        mode: String,
        projectExpectedPath: String?,
        preResolutionIdentity: [String: Any],
        frontDocumentPath: FrontDocumentPathProvider
    ) async -> String? {
        // Step 2 — mode. Release 1 only supports duplicate_applyback;
        // confirmed_live is refused BEFORE any write (P1-C, AC17).
        guard mode == "duplicate_applyback" else {
            return HonestContract.encodeV2StateC(
                error: .unsupportedMode,
                extras: [
                    "operation": operation,
                    "target_identity": preResolutionIdentity,
                    "what_was_attempted": "validate write mode '\(mode)'",
                    "what_was_observed": "mode '\(mode)' is not supported in Release 1 (only duplicate_applyback)",
                    "safe_to_retry": false,
                    "write_attempted": false,
                ]
            )
        }

        // Step 3 — project path gate (R10). Path is mandatory for duplicate
        // mutating ops (AC19), then the front document must match it (AC15).
        guard let expectedPath = projectExpectedPath,
              !expectedPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return HonestContract.encodeV2StateC(
                error: .projectPathRequired,
                extras: [
                    "operation": operation,
                    "target_identity": preResolutionIdentity,
                    "what_was_attempted": "verify the front document before writing",
                    "what_was_observed": "project_expected_path was not provided for a duplicate_applyback mutating op",
                    "safe_to_retry": false,
                    "write_attempted": false,
                ]
            )
        }
        let observedPath = await frontDocumentPath()
        guard let observedPath, AppleScriptChannel.projectPathsMatch(expectedPath, observedPath) else {
            var identity = preResolutionIdentity
            identity["project_path_expected"] = expectedPath
            identity["project_path_observed"] = observedPath ?? NSNull()
            return HonestContract.encodeV2StateC(
                error: .projectIdentityMismatch,
                extras: [
                    "operation": operation,
                    "target_identity": identity,
                    "what_was_attempted": "verify front document is the expected duplicate before writing",
                    "what_was_observed": observedPath == nil
                        ? "no front document path could be read"
                        : "front document path did not match project_expected_path",
                    "safe_to_retry": false,
                    "write_attempted": false,
                ]
            )
        }
        return nil
    }

    // MARK: - set_param_verified (R6 single precedence; AC10/AC11/AC17/AC19/AC23)

    /// Verified parameter write entry. The R6 single precedence, in order:
    ///
    ///   1  schema/params (`invalid_params`)
    ///   2  mode          (`unsupported_mode`)
    ///   3  project path  (`project_path_required` / `project_identity_mismatch`)
    ///   4  identity alias resolution (`unknown_plugin_identity`)
    ///   5  capability preflight — `.unsupported`/`.unknownParameter` fail closed
    ///      with `unsupported_param_readback` (AC10); only `.writeReadback`
    ///      proceeds.
    ///   6  track verified select (`track_selection_failed`)
    ///   7  inventory complete + occupied at `insert` (`incomplete_inventory`)
    ///   8  plugin window: already-open match, else open (`window_open_failed`)
    ///   9  slider match by AXDescription (`param_control_not_found`)
    ///  10  before `AXValue` read
    ///  11  set `AXValue` (`ax_write_failed`)
    ///  12  after `AXValue` + `AXValueDescription` read (`readback_lost_after_write`)
    ///  13  tolerance: |after - requested| <= tolerance ⇒ State A; else State C
    ///      `readback_mismatch` + rollback to the before value.
    ///
    /// Step 4 runs BEFORE step 5 so a display-name/alias input still reaches the
    /// capability lookup (canonical id is required to query capability — AC23).
    ///
    /// T5 wires the live write/readback path for the FIRST verified-writable
    /// parameter, Compressor `threshold` (normalized %, T0 spike). Every other
    /// parameter has no write/readback method, so step 5 still fail-closes it
    /// with `unsupported_param_readback` and no write is attempted.
    static func defaultSetParamVerified(
        params: [String: String],
        runtime: AXLogicProElements.Runtime = .production,
        frontDocumentPath: FrontDocumentPathProvider = liveFrontDocumentPath,
        pluginWindowOpener: PluginWindowOpener = liveNoOpPluginWindowOpener
    ) async -> ChannelResult {
        let operation = "logic_plugins.set_param_verified"

        // Step 1 — schema / params (presence, type, range, unit).
        guard let trackRaw = params["track"], let track = Int(trackRaw), track >= 0 else {
            return .error(invalidParamsStateC(operation, "missing or invalid 'track' (Int >= 0)"))
        }
        guard let insertRaw = params["insert"], let insert = Int(insertRaw), insert >= 0 else {
            return .error(invalidParamsStateC(operation, "missing or invalid 'insert' (Int >= 0)"))
        }
        let pluginAlias = params["plugin"] ?? ""
        guard !pluginAlias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .error(invalidParamsStateC(operation, "missing 'plugin' identity"))
        }
        let paramAlias = params["param"] ?? ""
        guard !paramAlias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .error(invalidParamsStateC(operation, "missing 'param' key"))
        }
        guard let valueRaw = params["value"], let value = Double(valueRaw), value.isFinite else {
            return .error(invalidParamsStateC(operation, "missing or non-finite 'value'"))
        }
        let unit = params["unit"]
        let mode = params["mode"] ?? ""

        let preResolutionIdentity: [String: Any] = [
            "track_index": track,
            "plugin_id_requested": pluginAlias,
        ]

        // Steps 2-3 — mode + project path gate (precedence: path-mismatch wins
        // over a later unsupported-param, AC23).
        if let gate = await verifiedModeAndPathGate(
            operation: operation,
            mode: mode,
            projectExpectedPath: params["project_expected_path"],
            preResolutionIdentity: preResolutionIdentity,
            frontDocumentPath: frontDocumentPath
        ) {
            return .error(gate)
        }

        // Step 4 — identity alias resolution (canonical id needed for step 5).
        guard let pluginID = VerifiedPluginCatalog.canonicalPluginID(from: pluginAlias) else {
            return .error(HonestContract.encodeV2StateC(
                error: .unknownPluginIdentity,
                extras: [
                    "operation": operation,
                    "target_identity": preResolutionIdentity,
                    "what_was_attempted": "resolve plugin identity '\(pluginAlias)' to a canonical catalog id",
                    "what_was_observed": "no alias mapping to a logic.stock.* id",
                    "safe_to_retry": false,
                    "write_attempted": false,
                ]
            ))
        }
        guard let paramKey = VerifiedPluginCatalog.canonicalParamKey(pluginID: pluginID, alias: paramAlias) else {
            return .error(HonestContract.encodeV2StateC(
                error: .unknownPluginIdentity,
                extras: [
                    "operation": operation,
                    "target_identity": resolvedIdentity(track: track, insert: insert, pluginID: pluginID),
                    "what_was_attempted": "resolve parameter '\(paramAlias)' for \(pluginID)",
                    "what_was_observed": "no parameter alias mapping for this plugin",
                    "safe_to_retry": false,
                    "write_attempted": false,
                ]
            ))
        }

        // Unit honesty (R8): a caller unit that disagrees with the declared
        // canonical unit is invalid_params.
        if let unit, let expectedUnit = VerifiedPluginCatalog.paramUnit(pluginID: pluginID, paramKey: paramKey),
           unit.caseInsensitiveCompare(expectedUnit) != .orderedSame {
            return .error(invalidParamsStateC(
                operation,
                "unit '\(unit)' does not match the declared unit '\(expectedUnit)' for \(pluginID).\(paramAlias)"
            ))
        }
        // Range validation (R6 step 1) against the declared display range.
        if let range = VerifiedPluginCatalog.paramRange(pluginID: pluginID, paramKey: paramKey),
           value < range.min || value > range.max {
            return .error(invalidParamsStateC(
                operation,
                "value \(value) is outside the valid range [\(range.min), \(range.max)] for \(pluginID).\(paramAlias)"
            ))
        }

        // Step 5 — capability preflight. Only `.writeReadback` (Compressor
        // threshold, T0 spike) proceeds to the live write; every other parameter
        // has no write/readback method and fail-closes BEFORE any write (AC10).
        let capability = VerifiedPluginCatalog.paramCapability(pluginID: pluginID, paramKey: paramKey)
        switch capability {
        case .unknownParameter, .unsupported:
            return .error(HonestContract.encodeV2StateC(
                error: .unsupportedParamReadback,
                extras: [
                    "operation": operation,
                    "target_identity": resolvedIdentity(track: track, insert: insert, pluginID: pluginID),
                    "param": paramAlias,
                    "what_was_attempted": "preflight write/readback capability for \(pluginID).\(paramAlias)",
                    "what_was_observed": capability == .unknownParameter
                        ? "parameter is not in the verified allowlist"
                        : "no display-readback parser / write method is available for this parameter",
                    "safe_to_retry": false,
                    "write_attempted": false,
                ]
            ))
        case .writeReadback:
            // Steps 6-13 — the live AX write/readback round-trip.
            return await performVerifiedParamWrite(
                operation: operation,
                track: track,
                insert: insert,
                pluginID: pluginID,
                paramKey: paramKey,
                paramAlias: paramAlias,
                requested: value,
                runtime: runtime,
                pluginWindowOpener: pluginWindowOpener
            )
        }
    }

    // MARK: - set_param_verified live write/readback (R6 steps 6-13)

    /// The live AX write/readback round-trip for a `.writeReadback` parameter.
    /// Reached ONLY after steps 1-5 pass, so identity/mode/path/capability are
    /// already validated. Every failure is a terminal HC v2 State C; success is
    /// State A with the full requested/observed payload. No State A is ever
    /// emitted unless an actual `AXValue` write landed AND the read-back value
    /// matched within tolerance.
    private static func performVerifiedParamWrite(
        operation: String,
        track: Int,
        insert: Int,
        pluginID: String,
        paramKey: String,
        paramAlias: String,
        requested: Double,
        runtime: AXLogicProElements.Runtime,
        pluginWindowOpener: PluginWindowOpener
    ) async -> ChannelResult {
        let identity = resolvedIdentity(track: track, insert: insert, pluginID: pluginID)
        guard let axDescription = VerifiedPluginCatalog.paramAXDescription(pluginID: pluginID, paramKey: paramKey) else {
            // A `.writeReadback` parameter must declare its AX matcher; absence is
            // a catalog defect, surfaced honestly rather than guessed around.
            return .error(HonestContract.encodeV2StateC(
                error: .unsupportedParamReadback,
                extras: [
                    "operation": operation,
                    "target_identity": identity,
                    "param": paramAlias,
                    "what_was_attempted": "resolve the AX control matcher for \(pluginID).\(paramAlias)",
                    "what_was_observed": "parameter declares no AX description matcher",
                    "safe_to_retry": false,
                    "write_attempted": false,
                ]
            ))
        }
        let tolerance = VerifiedPluginCatalog.paramTolerance(pluginID: pluginID, paramKey: paramKey) ?? 1.0

        // Step 6 — track verified select. Drive the AX-native selection ladder,
        // then confirm the target header reads back as selected (a write that the
        // AX API accepted vacuously must not be trusted — v3.0.9 lesson).
        guard AXLogicProElements.selectTrackViaAX(at: track, runtime: runtime) else {
            return .error(trackSelectionFailedStateC(operation, identity, "AX track selection write failed for track \(track)"))
        }
        guard await verifiedTrackSelected(track: track, runtime: runtime) else {
            return .error(trackSelectionFailedStateC(
                operation, identity,
                "track \(track) selection could not be verified via AXSelected readback"
            ))
        }

        // Step 7 — inventory complete + slot occupied at `insert` (reuse the
        // drift-safe enumerator; an unreadable chain or an empty target slot
        // means there is no plugin to write into).
        guard let mixer = AXLogicProElements.getMixerArea(runtime: runtime) else {
            return .error(incompleteInventoryStateC(operation, identity, "mixer area was not locatable"))
        }
        let strips = AXLogicProElements.mixerChannelStrips(in: mixer, runtime: runtime.ax)
        guard track < strips.count else {
            return .error(incompleteInventoryStateC(operation, identity, "track index \(track) is not present in the visible mixer"))
        }
        let slots = AXLogicProElements.audioPluginInsertSlots(in: strips[track], runtime: runtime.ax)
        let inventory = pluginInventoryItems(for: slots)
        guard inventory.complete else {
            return .error(incompleteInventoryStateC(operation, identity, "one or more insert slots are unreadable (complete:false)"))
        }
        guard insert < slots.count, slots[insert].occupied else {
            return .error(HonestContract.encodeV2StateC(
                error: .incompleteInventory,
                extras: [
                    "operation": operation,
                    "target_identity": identity,
                    "what_was_attempted": "locate the occupied plugin at insert \(insert)",
                    "what_was_observed": insert < slots.count
                        ? "insert \(insert) is empty — no plugin to write into"
                        : "insert \(insert) is out of range (\(slots.count) slots)",
                    "safe_to_retry": false,
                    "write_attempted": false,
                ]
            ))
        }

        // Step 8 — plugin window: prefer an already-open window titled with the
        // track name and exposing the matching slider; else attempt to open one.
        guard let trackName = AXLogicProElements.trackName(at: track, runtime: runtime) else {
            return .error(windowOpenFailedStateC(operation, identity, "the target track name could not be resolved for window matching"))
        }
        let window: AXUIElement
        if let open = AXLogicProElements.openPluginWindow(
            forTrackName: trackName, matchingSliderDescription: axDescription, runtime: runtime
        ) {
            window = open
        } else if let opened = await pluginWindowOpener(trackName, axDescription) {
            window = opened.element
        } else {
            return .error(windowOpenFailedStateC(
                operation, identity,
                "no open plugin window titled '\(trackName)' exposes the '\(axDescription)' control, and one could not be opened"
            ))
        }

        // Step 9 — slider match by AXDescription (the only stable identifier).
        guard let slider = AXLogicProElements.pluginWindowSlider(
            in: window, axDescription: axDescription, runtime: runtime.ax
        ) else {
            return .error(HonestContract.encodeV2StateC(
                error: .paramControlNotFound,
                extras: [
                    "operation": operation,
                    "target_identity": identity,
                    "param": paramAlias,
                    "what_was_attempted": "locate the '\(axDescription)' AXSlider in the plugin window",
                    "what_was_observed": "no slider with that AX description was found in the plugin window",
                    "safe_to_retry": false,
                    "write_attempted": false,
                ]
            ))
        }

        // Step 10 — read the before value (for rollback + provenance).
        let before = AXValueExtractors.extractSliderValue(slider, runtime: runtime.ax)

        // Step 11 — set AXValue (the actual write).
        guard AXValueExtractors.setSliderValue(slider, requested, runtime: runtime.ax) else {
            return .error(HonestContract.encodeV2StateC(
                error: .axWriteFailed,
                extras: [
                    "operation": operation,
                    "target_identity": identity,
                    "param": paramAlias,
                    "requested_normalized": requested,
                    "what_was_attempted": "set AXValue \(requested) on the '\(axDescription)' slider",
                    "what_was_observed": "the AX value write was rejected",
                    "safe_to_retry": true,
                    "write_attempted": true,
                ]
            ))
        }

        // Step 12 — read the after value (+ value description). A write that
        // cannot be read back is uncertain, not confirmed — fail closed.
        guard let after = AXValueExtractors.extractSliderValue(slider, runtime: runtime.ax) else {
            return .error(HonestContract.encodeV2StateC(
                error: .readbackLostAfterWrite,
                extras: [
                    "operation": operation,
                    "target_identity": identity,
                    "param": paramAlias,
                    "requested_normalized": requested,
                    "what_was_attempted": "read back the '\(axDescription)' slider value after writing",
                    "what_was_observed": "the slider value could not be read after the write",
                    "safe_to_retry": true,
                    "write_attempted": true,
                ]
            ))
        }
        let observedDisplay = AXValueExtractors.extractValueDescription(slider, runtime: runtime.ax)

        // Step 13 — tolerance gate.
        if abs(after - requested) <= tolerance {
            return .success(HonestContract.encodeV2StateA(extras: [
                "operation": operation,
                "target_identity": identity,
                "param": paramAlias,
                "requested_normalized": requested,
                "observed_normalized": after,
                "observed_display": observedDisplay ?? NSNull(),
                "display_unit": "%",
                "tolerance": tolerance,
                "write_source": "ax_plugin_window",
                "verify_source": "ax_plugin_window",
            ]))
        }

        // Mismatch — roll back to the before value (re-set + re-read) so a failed
        // verified write does not leave the parameter changed.
        let rollback = rollbackSliderValue(slider, to: before, runtime: runtime.ax)
        return .error(HonestContract.encodeV2StateC(
            error: .readbackMismatch,
            extras: [
                "operation": operation,
                "target_identity": identity,
                "param": paramAlias,
                "requested_normalized": requested,
                "observed_normalized": after,
                "observed_display": observedDisplay ?? NSNull(),
                "display_unit": "%",
                "tolerance": tolerance,
                "rollback_attempted": rollback.attempted,
                "rollback_succeeded": rollback.succeeded,
                "rollback_to": before ?? NSNull(),
                "what_was_attempted": "verify the '\(axDescription)' write within tolerance \(tolerance)",
                "what_was_observed": "observed \(after) differs from requested \(requested) beyond tolerance",
                "safe_to_retry": false,
                "write_attempted": true,
            ]
        ))
    }

    /// Roll a slider back to its pre-write value (re-set then re-read to confirm).
    /// Returns whether a rollback was attempted (only when a before value exists)
    /// and whether the re-read confirms it landed within a tight epsilon.
    private static func rollbackSliderValue(
        _ slider: AXUIElement,
        to before: Double?,
        runtime: AXHelpers.Runtime
    ) -> (attempted: Bool, succeeded: Bool) {
        guard let before else { return (false, false) }
        guard AXValueExtractors.setSliderValue(slider, before, runtime: runtime) else {
            return (true, false)
        }
        guard let restored = AXValueExtractors.extractSliderValue(slider, runtime: runtime) else {
            return (true, false)
        }
        return (true, abs(restored - before) <= 0.5)
    }

    private static func trackSelectionFailedStateC(_ operation: String, _ identity: [String: Any], _ detail: String) -> String {
        HonestContract.encodeV2StateC(
            error: .trackSelectionFailed,
            extras: [
                "operation": operation,
                "target_identity": identity,
                "what_was_attempted": "select the target track before writing",
                "what_was_observed": detail,
                "safe_to_retry": true,
                "write_attempted": false,
            ]
        )
    }

    private static func incompleteInventoryStateC(_ operation: String, _ identity: [String: Any], _ detail: String) -> String {
        HonestContract.encodeV2StateC(
            error: .incompleteInventory,
            extras: [
                "operation": operation,
                "target_identity": identity,
                "what_was_attempted": "read the insert inventory before writing",
                "what_was_observed": detail,
                "safe_to_retry": true,
                "write_attempted": false,
            ]
        )
    }

    private static func windowOpenFailedStateC(_ operation: String, _ identity: [String: Any], _ detail: String) -> String {
        HonestContract.encodeV2StateC(
            error: .windowOpenFailed,
            extras: [
                "operation": operation,
                "target_identity": identity,
                "what_was_attempted": "acquire the plugin window before writing",
                "what_was_observed": detail,
                "safe_to_retry": true,
                "write_attempted": false,
            ]
        )
    }

    /// Confirm the header at `track` reads back as AX-selected, retrying briefly
    /// (Logic commits selection asynchronously). Self-contained so the verified
    /// write path does not depend on the main channel's private selection
    /// verifier; uses the same `AXSelected` readback contract.
    private static func verifiedTrackSelected(
        track: Int,
        runtime: AXLogicProElements.Runtime
    ) async -> Bool {
        for attempt in 0..<6 {
            let headers = AXLogicProElements.allTrackHeaders(runtime: runtime)
            if track >= 0, track < headers.count,
               AXValueExtractors.extractSelectedState(headers[track], runtime: runtime.ax) == true {
                return true
            }
            if attempt < 5 {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        return false
    }

    // MARK: - insert_verified (Search-and-Add live insert → readback-gated State A)

    /// Structured result of one live "Search and Add Plug-in" attempt. The driver
    /// diffs the pre- vs post-insert inventory to detect WHERE the requested
    /// plugin actually landed (Search-and-Add chooses the slot, not the caller),
    /// and reports that physical `slot`. Only `.mounted` whose `slot` equals the
    /// requested `insert` becomes State A; a different slot is honest State C
    /// (`insert_landed_at_different_slot`), so a slot is never falsely confirmed.
    enum InsertDriverOutcome: Sendable {
        /// The requested plugin (`pluginID`) was observed newly mounted at the
        /// physical `slot` detected by the pre/post inventory diff. The gate maps
        /// `slot == insert` → State A, `slot != insert` → State C (after rollback).
        case mounted(slot: Int, pluginID: String, observedName: String?)
        /// The Search-and-Add path ran but the post-insert inventory readback
        /// could not be performed at all (mixer/strip unreadable). Uncertain →
        /// State C `post_insert_readback_unavailable` (fail-closed, not State B —
        /// a verified insert can never be uncertain-success).
        case readbackUnavailable
        /// Readback succeeded but the requested plugin did not appear at ANY slot
        /// after every result-selection strategy. The driver reports the name (if
        /// any) it last observed at the requested slot for diagnostics.
        case mountMismatch(observedName: String?)
        /// A TRANSIENT pre-mount setup step failed (the Search-and-Add UI was not
        /// ready: the Mix menu could not be clicked, the search field was not
        /// found, or no results loaded). No write was attempted. Distinct from the
        /// permanent `.mountMismatch` (every strategy ran but the plugin never
        /// mounted) — these are retry-able (`safe_to_retry:true`), P2-3.
        case transientSetupFailure(stage: String)
    }

    /// The injectable live-insert seam. Performs the entire "Mix > Search and Add
    /// Plug-in" sequence (mixer raise → menu → search field → result select+add →
    /// post-insert inventory readback) and returns a structured outcome plus a
    /// `select_trace` diagnostic dict. Injected so the gate→outcome→envelope
    /// mapping is unit-testable without ever issuing real CGEvent/menu actions;
    /// the production default (`liveSearchAndAddInsert`) is the only path that
    /// touches the live UI.
    typealias SearchAndAddInsertDriver = @Sendable (
        _ track: Int,
        _ insert: Int,
        _ pluginID: String,
        _ searchQuery: String,
        _ runtime: AXLogicProElements.Runtime
    ) async -> (outcome: InsertDriverOutcome, selectTrace: [String: Any])

    /// Injectable rollback seam for a stray/wrong-slot mount. Defaults to the
    /// live `verifiedUndoPluginInsert` (Edit-menu undo + readback confirmation);
    /// tests inject a fake so the gate's rollback reporting is hermetic (no live
    /// Logic / AppleScript).
    typealias PluginInsertRollback = @Sendable (
        _ track: Int,
        _ strayPluginID: String?,
        _ straySlot: Int?,
        _ runtime: AXLogicProElements.Runtime
    ) async -> RollbackResult

    static let liveInsertRollback: PluginInsertRollback = { track, strayPluginID, straySlot, runtime in
        await verifiedUndoPluginInsert(
            track: track, strayPluginID: strayPluginID, straySlot: straySlot, runtime: runtime
        )
    }

    /// Guarded verified insert entry. The write-preceding gates run live and are
    /// honest: schema → mode → project path → identity → inventory `complete:true`
    /// → slot-empty. Only after every gate passes does the op drive the live
    /// "Search and Add Plug-in" insert (R12 breakthrough), then a post-insert
    /// `get_inventory` readback (pre/post diff) is the SOLE State A precondition.
    ///
    /// State A is reachable ONLY when the readback observes the requested plugin
    /// newly mounted at the requested slot — a false verified insert is
    /// structurally impossible because the readback diff is the only State A path.
    ///
    /// `insert:K` honesty (R15 live): Search-and-Add lets Logic choose the slot
    /// (the first available audio-effect slot, observed live at insert 6, and at
    /// 1/7 in prior osascript runs — it is NOT caller-controllable). So the op
    /// detects WHERE the plugin actually landed and, if that differs from the
    /// requested `insert`, fails closed with `insert_landed_at_different_slot`
    /// (reporting `observed_slot`) and rolls the stray mount back — never a false
    /// "verified at K". `set_param_verified` State A is unaffected.
    static func defaultInsertVerified(
        params: [String: String],
        runtime: AXLogicProElements.Runtime = .production,
        frontDocumentPath: FrontDocumentPathProvider = liveFrontDocumentPath,
        insertDriver: SearchAndAddInsertDriver = liveSearchAndAddInsert,
        rollback: PluginInsertRollback = liveInsertRollback
    ) async -> ChannelResult {
        let operation = "logic_plugins.insert_verified"

        // Step 1 — schema.
        guard let trackRaw = params["track"], let track = Int(trackRaw), track >= 0 else {
            return .error(invalidParamsStateC(operation, "missing or invalid 'track' (Int >= 0)"))
        }
        guard let insertRaw = params["insert"], let insert = Int(insertRaw), insert >= 0 else {
            return .error(invalidParamsStateC(operation, "missing or invalid 'insert' (Int >= 0)"))
        }
        let pluginAlias = params["plugin"] ?? ""
        guard !pluginAlias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .error(invalidParamsStateC(operation, "missing 'plugin' identity"))
        }
        let mode = params["mode"] ?? ""

        let preResolutionIdentity: [String: Any] = [
            "track_index": track,
            "plugin_id_requested": pluginAlias,
        ]

        // Steps 2-3 — mode + project path gate.
        if let gate = await verifiedModeAndPathGate(
            operation: operation,
            mode: mode,
            projectExpectedPath: params["project_expected_path"],
            preResolutionIdentity: preResolutionIdentity,
            frontDocumentPath: frontDocumentPath
        ) {
            return .error(gate)
        }

        // Step 4 — identity (insert allowlist excludes Noise Gate, R5/R7).
        guard let pluginID = VerifiedPluginCatalog.canonicalPluginID(from: pluginAlias),
              insertableAllowlist.contains(pluginID) else {
            return .error(HonestContract.encodeV2StateC(
                error: .unknownPluginIdentity,
                extras: [
                    "operation": operation,
                    "target_identity": preResolutionIdentity,
                    "what_was_attempted": "resolve insertable plugin identity '\(pluginAlias)'",
                    "what_was_observed": "not an insertable allowlisted stock plugin (Gain / Channel EQ / Compressor)",
                    "safe_to_retry": false,
                    "write_attempted": false,
                ]
            ))
        }
        let identity = resolvedIdentity(track: track, insert: insert, pluginID: pluginID)

        // Step 5 — inventory must be complete + slot must be verified-empty
        // before an insert is even considered (R3/R7, AC5).
        guard let mixer = AXLogicProElements.getMixerArea(runtime: runtime) else {
            return .error(HonestContract.encodeV2StateC(
                error: .incompleteInventory,
                extras: [
                    "operation": operation,
                    "target_identity": identity,
                    "what_was_attempted": "read insert inventory before inserting",
                    "what_was_observed": "mixer area was not locatable",
                    "safe_to_retry": true,
                    "write_attempted": false,
                ]
            ))
        }
        let strips = AXLogicProElements.mixerChannelStrips(in: mixer, runtime: runtime.ax)
        guard track < strips.count else {
            return .error(HonestContract.encodeV2StateC(
                error: .incompleteInventory,
                extras: [
                    "operation": operation,
                    "target_identity": identity,
                    "what_was_attempted": "read insert inventory before inserting",
                    "what_was_observed": "track index \(track) is not present in the visible mixer",
                    "safe_to_retry": true,
                    "write_attempted": false,
                ]
            ))
        }
        let slots = AXLogicProElements.audioPluginInsertSlots(in: strips[track], runtime: runtime.ax)
        let built = pluginInventoryItems(for: slots)
        guard built.complete else {
            return .error(HonestContract.encodeV2StateC(
                error: .incompleteInventory,
                extras: [
                    "operation": operation,
                    "target_identity": identity,
                    "what_was_attempted": "verify the insert inventory is complete before inserting",
                    "what_was_observed": "one or more insert slots are unreadable (complete:false)",
                    "safe_to_retry": true,
                    "write_attempted": false,
                ]
            ))
        }
        guard insert < slots.count else {
            return .error(HonestContract.encodeV2StateC(
                error: .invalidParams,
                extras: [
                    "operation": operation,
                    "target_identity": identity,
                    "what_was_attempted": "address insert slot \(insert)",
                    "what_was_observed": "slot \(insert) is out of range (\(slots.count) slots)",
                    "safe_to_retry": false,
                    "write_attempted": false,
                ]
            ))
        }
        // `read_status == .empty` is the ONLY write-safe state — an
        // occupied-unreadable slot is never treated as empty (D4, AC21).
        guard slots[insert].isEmpty else {
            return .error(HonestContract.encodeV2StateC(
                error: .slotOccupied,
                extras: [
                    "operation": operation,
                    "target_identity": identity,
                    "existing_plugin_name": slots[insert].name ?? NSNull(),
                    "existing_read_status": slots[insert].readStatus.rawValue,
                    "what_was_attempted": "insert \(pluginID) into slot \(insert)",
                    "what_was_observed": "slot \(insert) is occupied (read_status=\(slots[insert].readStatus.rawValue))",
                    "safe_to_retry": false,
                    "write_attempted": false,
                ]
            ))
        }

        // Step 6 — drive the live Search-and-Add insert. The driver lets Logic
        // pick the slot, then diffs pre/post inventory to detect WHERE the
        // requested plugin actually landed, and reports that physical slot. State
        // A is reachable ONLY when the detected slot equals the requested `insert`
        // AND the identity matches — the readback diff is the only State A path.
        let searchQuery = StockPluginCatalog.entry(id: pluginID)?.displayName ?? pluginAlias
        let result = await insertDriver(track, insert, pluginID, searchQuery, runtime)
        let trace = result.selectTrace

        switch result.outcome {
        case let .mounted(observedSlot, observedID, observedName):
            // Identity must match (defensive — the driver only reports `.mounted`
            // for a newly-appeared requested plugin, but the gate stays the sole
            // State A authority).
            guard observedID == pluginID else {
                return .error(HonestContract.encodeV2StateC(
                    error: .postInsertPluginMismatch,
                    extras: [
                        "operation": operation,
                        "target_identity": identity,
                        "observed_plugin_id": observedID,
                        "observed_plugin_name": observedName ?? NSNull(),
                        "observed_slot": observedSlot,
                        "select_trace": trace,
                        "what_was_attempted": "verify the Search-and-Add insert is \(pluginID)",
                        "what_was_observed": "readback observed a different plugin \(observedID) at slot \(observedSlot)",
                        "safe_to_retry": false,
                        "write_attempted": true,
                    ]
                ))
            }
            // The plugin mounted, but Search-and-Add chose a slot. If it is not
            // the requested slot, do NOT confirm a slot we did not target — roll
            // the stray mount back and fail closed with the observed slot (R15:
            // exact slot targeting is unsupported in Release 1).
            guard observedSlot == insert else {
                let rollbackResult = await rollback(track, observedID, observedSlot, runtime)
                var extras: [String: Any] = [
                    "operation": operation,
                    "target_identity": identity,
                    "observed_plugin_id": observedID,
                    "observed_plugin_name": observedName ?? NSNull(),
                    "observed_slot": observedSlot,
                    "rollback_attempted": rollbackResult.attempted,
                    "rollback_succeeded": rollbackResult.succeeded,
                    "rollback_retries": rollbackResult.retries,
                    "rollback_last_click": rollbackResult.lastClickResult,
                    "select_trace": trace,
                    "what_was_attempted": "insert \(pluginID) at the requested slot \(insert) via Search and Add Plug-in",
                    "what_was_observed": "Search and Add placed \(pluginID) at slot \(observedSlot) (Logic chooses the slot; exact targeting is unsupported in Release 1)",
                    "safe_to_retry": false,
                    "write_attempted": true,
                ]
                // When the automatic rollback could NOT confirm removal, the stray
                // plugin is still mounted — guide an LLM agent to clean up manually
                // rather than leave it guessing (P3-b).
                if !rollbackResult.succeeded {
                    extras["recovery_action"] = "undo the last insert manually in Logic Pro (Edit > Undo) — the plugin remains mounted at slot \(observedSlot)"
                }
                return .error(HonestContract.encodeV2StateC(
                    error: .insertLandedAtDifferentSlot,
                    extras: extras
                ))
            }
            return .success(HonestContract.encodeV2StateA(extras: [
                "operation": operation,
                "target_identity": identity,
                "observed_plugin_id": observedID,
                "observed_plugin_name": observedName ?? NSNull(),
                "observed_slot": observedSlot,
                "select_trace": trace,
                "write_source": "ax_search_and_add",
                "verify_source": "ax_plugin_inventory",
            ]))

        case .readbackUnavailable:
            return .error(HonestContract.encodeV2StateC(
                error: .postInsertReadbackUnavailable,
                extras: [
                    "operation": operation,
                    "target_identity": identity,
                    "select_trace": trace,
                    "what_was_attempted": "read back the insert inventory after Search-and-Add",
                    "what_was_observed": "the mixer/strip insert subtree was unreadable after the insert",
                    "safe_to_retry": true,
                    "write_attempted": true,
                ]
            ))

        case let .mountMismatch(observedName):
            // Every result-selection strategy ran but the requested plugin never
            // appeared at the requested slot. Honest-deferred terminal: the
            // insert could not be verified in this Logic build. The driver has
            // already attempted rollback for any stray mount it observed.
            return .error(HonestContract.encodeV2StateC(
                error: .insertNotAxAutomatable,
                extras: [
                    "operation": operation,
                    "target_identity": identity,
                    "observed_plugin_name": observedName ?? NSNull(),
                    "select_trace": trace,
                    "what_was_attempted": "insert \(pluginID) into slot \(insert) via Mix > Search and Add Plug-in",
                    "what_was_observed": observedName == nil
                        ? "no plugin appeared at slot \(insert) after every Search-and-Add result-selection strategy"
                        : "slot \(insert) showed '\(observedName!)' which is not the requested \(pluginID) after every strategy",
                    "safe_to_retry": false,
                    "write_attempted": true,
                ]
            ))

        case let .transientSetupFailure(stage):
            // A pre-mount UI-setup step did not complete (menu/search-field/results
            // not ready). No write attempted → retry-able (P2-3), distinct from the
            // permanent insert_not_ax_automatable.
            return .error(HonestContract.encodeV2StateC(
                error: .insertSetupFailed,
                extras: [
                    "operation": operation,
                    "target_identity": identity,
                    "setup_stage": stage,
                    "select_trace": trace,
                    "what_was_attempted": "open the Search and Add Plug-in dialog and load results for \(pluginID)",
                    "what_was_observed": "the Search-and-Add UI was not ready at stage '\(stage)' — no insert was attempted",
                    "safe_to_retry": true,
                    "write_attempted": false,
                ]
            ))
        }
    }

    // MARK: - insert_verified live driver (Search and Add Plug-in)

    /// Locale-aware (menu-bar title, menu-item title) pairs for the
    /// "Mix > Search and Add Plug-in…" path. Korean primary, English fallback —
    /// Logic localises the menu bar, and the item shows a trailing ellipsis (the
    /// real `…` U+2026 and the ASCII `...` are both tried).
    private static let searchAndAddMenuCandidates: [(bar: String, item: String)] = [
        ("믹스", "플러그인 검색 및 추가…"),
        ("믹스", "플러그인 검색 및 추가..."),
        ("Mix", "Search and Add Plug-in…"),
        ("Mix", "Search and Add Plug-in..."),
    ]
    /// Window-menu "hide all plug-in windows" (menu-bar, menu-item) pairs.
    private static let hidePluginWindowsMenuCandidates: [(bar: String, item: String)] = [
        ("윈도우", "모든 플러그인 윈도우 가리기"),
        ("Window", "Hide All Plug-in Windows"),
    ]

    /// Production "Search and Add Plug-in" insert driver (R12). Drives the whole
    /// live sequence and returns a structured outcome plus a `select_trace`
    /// diagnostic dict. This is the ONLY path that issues real menu/CGEvent
    /// actions; `defaultInsertVerified` is unit-tested against an injected fake.
    ///
    /// Sequence:
    ///   0. hide any stray plugin windows (a front plugin window from a prior
    ///      attempt steals the menu — R14 live: AXPress menu nav opened the track
    ///      instrument window instead of the search dialog);
    ///   1. select the target track (so the Mix menu targets the right strip);
    ///   2. raise the mixer/main window via `AXRaise` (else the Mix menu item is
    ///      disabled — the R12 key finding);
    ///   3. click "Mix > Search and Add Plug-in…" via AppleScript (R14: AXPress
    ///      opened the wrong window; `click menu item ... of menu bar item ...`
    ///      reliably opens the search dialog), polling `enabled` first;
    ///   4. type the plugin name into the search dialog's `AXTextField` (AXValue
    ///      set first, keystroke fallback);
    ///   5. poll the results `AXOutline` until a row appears;
    ///   5b. EXACT-row verify (P2-4): read the first result row's text and, when
    ///      readable, require an exact (case-insensitive) match to the expected
    ///      display name before committing — if no exactly-matching row exists,
    ///      fail BEFORE any commit so a reordered "Squash Compressor"-type variant
    ///      is never mounted;
    ///   6. try each result-selection strategy in priority order — `return_only`
    ///      (commit the auto-highlighted first result; R18), then `row_double_click`
    ///      / `add_button_press` / `row_click_then_add_button` as fallbacks — and
    ///      after each, CONDITION-poll the inventory (P1-2: wait for an actual
    ///      change, not the first readable snapshot) and diff against the
    ///      pre-snapshot to detect WHERE the requested plugin landed;
    ///   7. report `.mounted(slot:)` with the detected physical slot — the gate
    ///      maps slot==insert to State A, slot!=insert to State C; a permanent
    ///      no-mount is `.mountMismatch` (insert_not_ax_automatable), a transient
    ///      UI-setup failure (menu/field/results not ready) is
    ///      `.transientSetupFailure` (insert_setup_failed, retry-able), and an
    ///      unreadable strip (pre OR post) is the retry-able `.readbackUnavailable`.
    static let liveSearchAndAddInsert: SearchAndAddInsertDriver = { track, insert, pluginID, searchQuery, runtime in
        var trace: [String: Any] = [
            "requested_track": track,
            "requested_insert": insert,
            "requested_plugin_id": pluginID,
            "search_query": searchQuery,
            "strategies_attempted": [String](),
        ]

        // 0 — clean state so the Mix menu becomes enabled and is not captured by a
        // stray window (R15 live: enabled=true needs all of these). (a) close any
        // leftover "위치로 이동" / "Go to Position" floating dialog from a prior AX
        // side effect, (b) hide all plug-in windows, (c) [step 2] raise the mixer.
        trace["go_to_position_closed"] = await closeGoToPositionDialog()
        trace["plugin_windows_hidden"] = await hideAllPluginWindows()
        try? await Task.sleep(for: .milliseconds(150))

        // 1 — select the target track via the AX-native ladder.
        let trackSelected = AXLogicProElements.selectTrackViaAX(at: track, runtime: runtime)
        trace["track_select_ok"] = trackSelected
        try? await Task.sleep(for: .milliseconds(150))

        // 2 — raise the mixer/main window so the Mix menu becomes enabled.
        trace["window_raised"] = raiseMixerWindow(runtime: runtime)
        try? await Task.sleep(for: .milliseconds(150))

        // Snapshot the FULL pre-insert inventory (slot → plugin_id) so a post-
        // insert diff can detect WHERE the new plugin landed (Search-and-Add
        // chooses the slot; R15 live observed insert 6, not the requested slot).
        let preSnapshot = fullStripInventory(track: track, runtime: runtime)
        trace["pre_inventory_readable"] = (preSnapshot != nil)

        // A readable pre-snapshot is REQUIRED to diff against — without it every
        // occupied slot would look "new" (false State A) AND a stray mount could
        // not be rolled back (`newlyMountedAnyPlugin` needs the baseline). A nil
        // snapshot is a TRANSIENT condition (the mixer/strip was momentarily
        // unreadable), so bail out BEFORE driving any UI with the retry-able
        // `.readbackUnavailable` (`safe_to_retry:true`) — NOT `.mountMismatch`
        // (`insert_not_ax_automatable`, `safe_to_retry:false`), which would
        // mislabel a transient read failure as a permanent AX limitation (P2).
        guard let preInventory = preSnapshot else {
            return (.readbackUnavailable, trace)
        }

        // 3 — open Mix > Search and Add Plug-in… via AppleScript click. The menu
        // `enabled` state is polled first (channel-strip focus sync is flaky:
        // AXRaise alone is not always enough), and an AppleScript `click menu
        // item` is used instead of an AX `AXPress` (R14: AXPress on this item
        // opened the track instrument plugin window, not the search dialog).
        let menuResult = await openSearchAndAddViaAppleScript()
        trace["menu_press_method"] = "applescript_click"
        trace["enabled_retries"] = menuResult.enabledRetries
        trace["menu_item_found"] = menuResult.itemFound
        trace["menu_pressed"] = menuResult.clicked
        guard menuResult.clicked else {
            // Transient: the Mix menu could not be clicked (UI not ready / not
            // enabled) — no write attempted, retry-able (P2-3).
            return (.transientSetupFailure(stage: "mix_menu_click"), trace)
        }
        try? await Task.sleep(for: .milliseconds(400))

        // 4 — locate the search field. Live structure (R12): the search field is
        // an `AXTextField` nested inside an `AXGroup` (NOT a window-direct child),
        // and right after the menu press it is the systemwide focused element.
        // Prefer the focused element; fall back to a RECURSIVE dialog search so a
        // window-direct-only scan can no longer miss it.
        let fieldResult = locateSearchField(runtime: runtime)
        guard let field = fieldResult.field else {
            trace["search_field_found"] = false
            trace["search_field_via"] = fieldResult.via
            AXMouseHelper.pressEscape()
            // Transient: the search dialog/field was not located — retry-able (P2-3).
            return (.transientSetupFailure(stage: "search_field_not_found"), trace)
        }
        trace["search_field_found"] = true
        trace["search_field_via"] = fieldResult.via
        let typed = typeSearchQuery(searchQuery, into: field, runtime: runtime.ax)
        trace["search_query_set"] = typed
        let fieldValue: String? = AXHelpers.getAttribute(field, kAXValueAttribute as String, runtime: runtime.ax)
        trace["search_field_value"] = fieldValue ?? NSNull()

        // 5 — results live in the SAME container as the search field: the field's
        // parent `AXGroup` holds an `AXScrollArea > AXOutline` sibling. Search up
        // from the field for that container, then poll its outline for rows.
        let resultsContainer = searchResultsContainer(forField: field, runtime: runtime.ax)
            ?? searchAndAddDialog(runtime: runtime)
        trace["results_container_found"] = (resultsContainer != nil)
        let resultsReady: [AXUIElement]
        if let resultsContainer {
            resultsReady = await pollResultRows(in: resultsContainer, runtime: runtime.ax, timeoutMs: 2_000)
        } else {
            resultsReady = []
        }
        trace["result_rows"] = resultsReady.count
        // `resultsContainer` is non-nil here: rows were enumerated from it.
        guard let firstRow = resultsReady.first, let container = resultsContainer else {
            AXMouseHelper.pressEscape()
            // Transient: results did not load (search still indexing / dialog not
            // ready) — no write attempted, retry-able (P2-3).
            return (.transientSetupFailure(stage: "no_result_rows"), trace)
        }

        // P2-4 — exact-row verification BEFORE committing. `return_only` commits
        // the auto-highlighted first row; if Logic reordered results (locale /
        // version / install variance), that first row could be a wrong variant
        // (e.g. "Squash Compressor" for a "Compressor" query). Read the first row's
        // text and, when readable, require an EXACT match to the expected display
        // name before any commit. When the text is unreadable we proceed (the
        // post-insert readback diff still blocks a wrong variant as State C).
        let firstRowText = resultRowText(firstRow, runtime: runtime.ax)
        trace["first_result_row_text"] = firstRowText ?? NSNull()
        trace["expected_result_name"] = searchQuery
        if let firstRowText, firstRowText.caseInsensitiveCompare(searchQuery) != .orderedSame {
            // Look for an exactly-matching row elsewhere in the result set; if none
            // exists, fail BEFORE committing rather than mount a wrong variant.
            let exactMatch = resultsReady.first {
                resultRowMatchesExpected($0, expectedName: searchQuery, runtime: runtime.ax)
            }
            guard exactMatch != nil else {
                AXMouseHelper.pressEscape()
                trace["exact_row_match"] = false
                return (.mountMismatch(observedName: firstRowText), trace)
            }
            trace["exact_row_match"] = true
        }

        // 6 — try each result-selection strategy, then diff the FULL inventory
        // against the pre-insert snapshot to detect WHERE the requested plugin
        // newly appeared (Search-and-Add chooses the slot — R15). The first
        // strategy after which the requested plugin newly appears at SOME slot
        // wins; that detected slot is reported so the gate can compare it to the
        // requested `insert`. Strategies that need the add button scan `container`
        // (the field's parent group) where the '추가'/Add AXButton lives.
        var strategiesTried: [String] = []
        var anyPostReadbackSucceeded = false
        for strategy in resultSelectionStrategies {
            strategiesTried.append(strategy.name)
            strategy.run(container, firstRow, runtime.ax)

            // P1-2: CONDITION-poll for the inventory to actually CHANGE (the
            // requested plugin appeared, or some stray did) rather than settling on
            // the first merely-readable snapshot — a slow Logic commit could
            // otherwise return the unchanged pre-insert state and drive a false
            // "nothing mounted" → premature next strategy / mislabel. `preInventory`
            // is guaranteed non-nil here (guarded before the menu press).
            let poll = await pollStripInventoryUntil(
                track: track, runtime: runtime, timeoutMs: 1_500
            ) { inv in
                newlyMountedSlot(pluginID: pluginID, pre: preInventory, post: inv) != nil
                    || newlyMountedAnyPlugin(pre: preInventory, post: inv) != nil
            }
            guard let postInventory = poll.satisfied ?? poll.lastReadable else {
                continue  // strip stayed unreadable this whole window
            }
            anyPostReadbackSucceeded = true

            // A slot that did NOT hold the requested plugin before but does now is
            // the freshly-mounted target. (Identity is matched here; the gate
            // re-checks slot==insert.)
            if let detected = newlyMountedSlot(
                pluginID: pluginID, pre: preInventory, post: postInventory
            ) {
                trace["strategies_attempted"] = strategiesTried
                trace["winning_strategy"] = strategy.name
                trace["observed_slot"] = detected.slot
                trace["observed_name"] = detected.name ?? NSNull()
                return (.mounted(slot: detected.slot, pluginID: pluginID, observedName: detected.name), trace)
            }

            // If SOME other (non-requested) plugin newly appeared — including a
            // non-allowlisted one whose canonical id is nil — roll it back so a
            // wrong-plugin mount is not left behind before the next strategy. The
            // observed display name lets the rollback confirm removal even when the
            // id is nil (P1-1).
            if let stray = newlyMountedAnyPlugin(pre: preInventory, post: postInventory) {
                trace["stray_mount_plugin_id"] = stray.pluginID ?? NSNull()
                trace["stray_mount_name"] = stray.name ?? NSNull()
                let rollback = await verifiedUndoPluginInsert(
                    track: track, strayPluginID: stray.pluginID, straySlot: stray.slot,
                    strayName: stray.name, runtime: runtime
                )
                trace["stray_rollback_succeeded"] = rollback.succeeded
            }
        }
        trace["strategies_attempted"] = strategiesTried

        // Dismiss any still-open dialog, then classify the final state. If NO
        // post-strategy poll was ever readable, the strip went unreadable mid-op
        // → retry-able `.readbackUnavailable`; otherwise readback worked but the
        // requested plugin never appeared anywhere → honest `.mountMismatch`.
        AXMouseHelper.pressEscape()
        if !anyPostReadbackSucceeded {
            return (.readbackUnavailable, trace)
        }
        return (.mountMismatch(observedName: nil), trace)
    }

    // MARK: - insert_verified live driver helpers

    /// Raise the window that contains the visible mixer (the R12 key step — the
    /// Mix menu item is disabled until the mixer window is frontmost). Falls back
    /// to the main window. Returns whether an `AXRaise` was issued.
    private static func raiseMixerWindow(runtime: AXLogicProElements.Runtime) -> Bool {
        guard let app = AXLogicProElements.appRoot(runtime: runtime) else { return false }
        let windows: [AXUIElement] = AXHelpers.getAttribute(
            app, kAXWindowsAttribute as String, runtime: runtime.ax
        ) ?? []
        // Prefer a window that actually holds a mixer area; else the main window.
        for window in windows {
            if AXHelpers.findDescendant(
                of: window, role: kAXGroupRole as String, identifier: "Mixer", maxDepth: 6, runtime: runtime.ax
            ) != nil {
                return AXHelpers.performAction(window, kAXRaiseAction as String, runtime: runtime.ax)
            }
        }
        if let main = AXLogicProElements.mainWindow(runtime: runtime) {
            return AXHelpers.performAction(main, kAXRaiseAction as String, runtime: runtime.ax)
        }
        return false
    }

    /// Click "Mix > Search and Add Plug-in…" via AppleScript (`click menu item …
    /// of menu 1 of menu bar item … of menu bar 1`). R14 live: an AX `AXPress`
    /// on this item opened the track instrument plugin window instead of the
    /// search dialog, while the AppleScript click reliably opens the search
    /// dialog. The menu `enabled` state is polled first (channel-strip focus sync
    /// is flaky: AXRaise alone is not always enough), forcing the mixer window to
    /// the front and re-raising between attempts. Returns whether the item was
    /// found/clicked and how many enabled-poll iterations were needed.
    private static func openSearchAndAddViaAppleScript(
        maxEnabledRetries: Int = 8
    ) async -> (itemFound: Bool, clicked: Bool, enabledRetries: Int) {
        var itemFound = false
        for attempt in 0..<maxEnabledRetries {
            for candidate in searchAndAddMenuCandidates {
                let probe = await runMenuItemAppleScript(
                    bar: candidate.bar, item: candidate.item, action: .checkEnabled
                )
                switch probe {
                case .missing:
                    continue  // wrong locale / item label — try the next candidate
                case .disabled:
                    itemFound = true  // exists but not yet enabled — retry below
                case .ok:
                    itemFound = true
                    let click = await runMenuItemAppleScript(
                        bar: candidate.bar, item: candidate.item, action: .click
                    )
                    if click == .ok {
                        return (true, true, attempt)
                    }
                }
            }
            // Not enabled yet (or click failed): nudge focus to the mixer window
            // and wait briefly before re-polling.
            _ = forceMixerWindowFront()
            try? await Task.sleep(for: .milliseconds(250))
        }
        return (itemFound, false, maxEnabledRetries)
    }

    /// Hide every open plug-in window via "Window > Hide All Plug-in Windows" so a
    /// stray front plugin window (e.g. a track instrument window left open by a
    /// prior attempt) cannot capture the subsequent Mix-menu click (R14 live root
    /// cause). Best-effort: returns whether the menu item was clicked.
    @discardableResult
    private static func hideAllPluginWindows() async -> Bool {
        for candidate in hidePluginWindowsMenuCandidates {
            let result = await runMenuItemAppleScript(
                bar: candidate.bar, item: candidate.item, action: .click
            )
            if result == .ok { return true }
        }
        return false
    }

    /// Outcome of an AppleScript menu-item probe/click.
    private enum MenuItemScriptResult: String {
        case ok
        case disabled
        case missing
    }

    private enum MenuItemScriptAction {
        case checkEnabled
        case click
    }

    /// Run an AppleScript that targets a single `menu item <item> of menu 1 of
    /// menu bar item <bar> of menu bar 1` of the Logic Pro process and either
    /// checks `enabled` or clicks it. Activates Logic first so the menu bar is
    /// live. Reuses `AppleScriptChannel.executeAppleScript` (in-process
    /// NSAppleScript with TCC inheritance + osascript fallback, no FD leak).
    private static func runMenuItemAppleScript(
        bar: String, item: String, action: MenuItemScriptAction
    ) async -> MenuItemScriptResult {
        let barLit = appleScriptStringLiteral(bar)
        let itemLit = appleScriptStringLiteral(item)
        let body: String
        switch action {
        case .checkEnabled:
            body = """
                    set mi to menu item \(itemLit) of menu 1 of menu bar item \(barLit) of menu bar 1
                    if enabled of mi then
                        return "ok"
                    else
                        return "disabled"
                    end if
            """
        case .click:
            body = """
                    click menu item \(itemLit) of menu 1 of menu bar item \(barLit) of menu bar 1
                    return "ok"
            """
        }
        let script = """
        tell application "Logic Pro" to activate
        delay 0.1
        tell application "System Events"
            tell process "Logic Pro"
                try
        \(body)
                on error
                    return "missing"
                end try
            end tell
        end tell
        """
        let result = await AppleScriptChannel.executeAppleScript(script)
        let text = AppleScriptChannel.appleScriptResultText(from: result)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "missing"
        return MenuItemScriptResult(rawValue: text) ?? .missing
    }

    /// Click the FIRST enabled Edit-menu undo item by PREFIX, via AppleScript.
    /// Logic appends the specific action to the undo label (e.g. "실행 취소
    /// 채널 스트립의 플러그인 삽입" / "Undo Insert Plug-in on Channel Strip"), so the
    /// exact-title click is brittle. This matches the localized undo PREFIX
    /// ("실행 취소" / "Undo"), only clicks it when `enabled`, and reports the
    /// result — so a disabled (nothing-to-undo) item is honestly `disabled`, not
    /// a false `ok`. R16 live: the exact-label `undoPluginInsert` reported `ok`
    /// but did not remove the stray Gain (label mismatch / disabled at click).
    private static func clickEditUndoViaAppleScript() async -> MenuItemScriptResult {
        for bar in ["편집", "Edit"] {
            for prefix in ["실행 취소", "Undo"] {
                let barLit = appleScriptStringLiteral(bar)
                let prefixLit = appleScriptStringLiteral(prefix)
                let script = """
                tell application "Logic Pro" to activate
                delay 0.1
                tell application "System Events"
                    tell process "Logic Pro"
                        try
                            set undoItems to (every menu item of menu 1 of menu bar item \(barLit) of menu bar 1 whose name starts with \(prefixLit))
                            if (count of undoItems) is 0 then return "missing"
                            set mi to item 1 of undoItems
                            if not (enabled of mi) then return "disabled"
                            click mi
                            return "ok"
                        on error
                            return "missing"
                        end try
                    end tell
                end tell
                """
                let result = await AppleScriptChannel.executeAppleScript(script)
                let text = AppleScriptChannel.appleScriptResultText(from: result)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "missing"
                switch MenuItemScriptResult(rawValue: text) ?? .missing {
                case .ok: return .ok
                case .disabled: return .disabled   // nothing to undo under this locale
                case .missing: continue            // wrong locale — try next
                }
            }
        }
        return .missing
    }

    /// Force the mixer-bearing window to the AX front (`AXMain` + `AXFocused`
    /// true) and re-raise it. Used between enabled-poll iterations to coax Logic
    /// into syncing channel-strip focus so the Mix menu becomes enabled.
    private static func forceMixerWindowFront() -> Bool {
        guard let app = AXLogicProElements.appRoot(runtime: .production) else { return false }
        let windows: [AXUIElement] = AXHelpers.getAttribute(
            app, kAXWindowsAttribute as String, runtime: .production
        ) ?? []
        for window in windows where AXHelpers.findDescendant(
            of: window, role: kAXGroupRole as String, identifier: "Mixer", maxDepth: 6, runtime: .production
        ) != nil {
            _ = AXHelpers.setAttribute(window, kAXMainAttribute as String, true as CFTypeRef, runtime: .production)
            _ = AXHelpers.setAttribute(window, kAXFocusedAttribute as String, true as CFTypeRef, runtime: .production)
            return AXHelpers.performAction(window, kAXRaiseAction as String, runtime: .production)
        }
        return raiseMixerWindow(runtime: .production)
    }

    /// AppleScript double-quoted string literal with full escaping (backslash,
    /// quote, and newline/CR → `\n`/`\r`).
    ///
    /// SCOPE / SAFETY: every caller passes a CONTROLLED STATIC menu string (the
    /// locale-keyed menu-bar/item labels declared as `let` constants above) —
    /// never runtime-variable data. Runtime values (the plugin name / search
    /// query) are injected through AX (`AXValue` set) or CGEvent keystrokes, NOT
    /// AppleScript string interpolation, so untrusted input never reaches a
    /// generated script. The `\`/`"` escaping is the load-bearing defense for the
    /// static labels; newline/CR escaping is added defensively so a future caller
    /// passing a multi-line string cannot break out of the literal. If a
    /// runtime-VARIABLE string is ever passed in, prefer AX/CGEvent injection over
    /// AppleScript interpolation regardless.
    private static func appleScriptStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return "\"\(escaped)\""
    }

    /// Locate the Search-and-Add search `AXTextField`. R12 live structure: the
    /// field is NOT a window-direct child — it sits inside an `AXGroup`
    /// (`AXGroup{AXImage, AXTextField, AXButton, AXScrollArea > AXOutline}`) and
    /// is the systemwide focused element right after the menu press.
    ///
    /// Priority:
    ///   1. `kAXFocusedUIElementAttribute` on the app — if it is an `AXTextField`,
    ///      that IS the search field (a `keystroke` already lands in it live);
    ///   2. fall back to a RECURSIVE descendant search of the matched dialog
    ///      window (a window-direct-only scan would miss the nested field).
    /// Returns the field and which path found it (for `select_trace`).
    private static func locateSearchField(
        runtime: AXLogicProElements.Runtime
    ) -> (field: AXUIElement?, via: String) {
        if let app = AXLogicProElements.appRoot(runtime: runtime),
           let focused: AXUIElement = AXHelpers.getAttribute(
               app, kAXFocusedUIElementAttribute as String, runtime: runtime.ax
           ),
           (AXHelpers.getRole(focused, runtime: runtime.ax) ?? "") == (kAXTextFieldRole as String) {
            return (focused, "focused_element")
        }
        if let dialog = searchAndAddDialog(runtime: runtime),
           let field = AXHelpers.findDescendant(
               of: dialog, role: kAXTextFieldRole as String, maxDepth: 8, runtime: runtime.ax
           ) {
            return (field, "dialog_recursive")
        }
        return (nil, "not_found")
    }

    /// From the search field, walk up to the nearest ancestor `AXGroup` that also
    /// contains the results `AXScrollArea > AXOutline` (the live shape: field and
    /// results are siblings under one group). Returns that container, or nil when
    /// no ancestor holds an outline. Bounded ancestor walk (the parent chain is
    /// shallow: field → group → window).
    private static func searchResultsContainer(
        forField field: AXUIElement, runtime: AXHelpers.Runtime
    ) -> AXUIElement? {
        var current: AXUIElement? = field
        var depth = 0
        while let node = current, depth < 6 {
            if AXHelpers.findDescendant(
                of: node, role: kAXOutlineRole as String, maxDepth: 6, runtime: runtime
            ) != nil {
                return node
            }
            current = AXHelpers.getAttribute(node, kAXParentAttribute as String, runtime: runtime)
            depth += 1
        }
        return nil
    }

    /// Locate the Search-and-Add search dialog: a window whose subtree exposes a
    /// text field next to a results outline (the R12-observed shape
    /// `AXGroup{AXImage, AXTextField, AXButton, AXScrollArea > AXOutline}`).
    private static func searchAndAddDialog(runtime: AXLogicProElements.Runtime) -> AXUIElement? {
        guard let app = AXLogicProElements.appRoot(runtime: runtime) else { return nil }
        let windows: [AXUIElement] = AXHelpers.getAttribute(
            app, kAXWindowsAttribute as String, runtime: runtime.ax
        ) ?? []
        for window in windows {
            let hasField = AXHelpers.findDescendant(
                of: window, role: kAXTextFieldRole as String, maxDepth: 6, runtime: runtime.ax
            ) != nil
            let hasOutline = AXHelpers.findDescendant(
                of: window, role: kAXOutlineRole as String, maxDepth: 6, runtime: runtime.ax
            ) != nil
            if hasField && hasOutline { return window }
        }
        return nil
    }

    /// Set the search field text: prefer a direct `AXValue` write, fall back to
    /// focus + Unicode keystroke (the field is a standard NSTextField, so the
    /// AXValue write usually lands).
    private static func typeSearchQuery(
        _ query: String, into field: AXUIElement, runtime: AXHelpers.Runtime
    ) -> Bool {
        if AXHelpers.setAttribute(field, kAXValueAttribute as String, query as CFTypeRef, runtime: runtime) {
            let readBack: String? = AXHelpers.getAttribute(field, kAXValueAttribute as String, runtime: runtime)
            if readBack == query { return true }
        }
        _ = AXHelpers.setAttribute(field, kAXFocusedAttribute as String, true as CFTypeRef, runtime: runtime)
        AXMouseHelper.typeText(query)
        return true
    }

    /// Poll the results outline for rows until at least one appears or the
    /// timeout elapses.
    private static func pollResultRows(
        in dialog: AXUIElement, runtime: AXHelpers.Runtime, timeoutMs: Int
    ) async -> [AXUIElement] {
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
        repeat {
            if let outline = AXHelpers.findDescendant(
                of: dialog, role: kAXOutlineRole as String, maxDepth: 6, runtime: runtime
            ) {
                let rows = AXHelpers.getChildren(outline, runtime: runtime).filter {
                    (AXHelpers.getRole($0, runtime: runtime) ?? "") == (kAXRowRole as String)
                }
                if !rows.isEmpty { return rows }
            }
            try? await Task.sleep(for: .milliseconds(120))
        } while Date() < deadline
        return []
    }

    /// Read a result row's display text (R12: row → AXCell → AXStaticText holds
    /// the plugin name; some builds expose it as the row's own title/value). Tries
    /// the cell static text first, then the row title/value, trimmed.
    private static func resultRowText(_ row: AXUIElement, runtime: AXHelpers.Runtime) -> String? {
        if let cellText = AXHelpers.findDescendant(
            of: row, role: kAXStaticTextRole as String, maxDepth: 4, runtime: runtime
        ) {
            if let v: String = AXHelpers.getAttribute(cellText, kAXValueAttribute as String, runtime: runtime),
               !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return v.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let t = AXHelpers.getTitle(cellText, runtime: runtime),
               !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return t.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if let t = AXHelpers.getTitle(row, runtime: runtime),
           !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return t.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let v: String = AXHelpers.getAttribute(row, kAXValueAttribute as String, runtime: runtime),
           !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return v.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    /// Whether a result row's text is an EXACT, case-insensitive match for the
    /// expected plugin display name (P2-4). Exact (not substring) so "Compressor"
    /// does not match "Squash Compressor" / "AUMultibandCompressor" / "Multipressor".
    private static func resultRowMatchesExpected(
        _ row: AXUIElement, expectedName: String, runtime: AXHelpers.Runtime
    ) -> Bool {
        guard let text = resultRowText(row, runtime: runtime) else { return false }
        return text.caseInsensitiveCompare(expectedName) == .orderedSame
    }

    /// One result-selection strategy: a named UI action that attempts to commit
    /// the first result into the first empty insert slot.
    private struct ResultSelectionStrategy: Sendable {
        let name: String
        let run: @Sendable (_ dialog: AXUIElement, _ firstRow: AXUIElement, _ runtime: AXHelpers.Runtime) -> Void
    }

    /// Result-selection strategies in priority order. R17 multi-plugin live:
    /// **Return only** (no Down) is the correct trigger — after typing, the search
    /// dialog already AUTO-HIGHLIGHTS the first result (the exact-name match), so a
    /// bare Return commits it. An extra Down moves selection to the SECOND row,
    /// which for a multi-result query mounts the wrong variant (e.g. "Compressor"
    /// search → Compressor / Squash Compressor / … ; Down+Return picked Squash).
    /// Verified live: Compressor (4 results), Channel EQ (1), Gain (1) all mount
    /// the exact match with Return only. The CGEvent double-click / add-button
    /// strategies failed live (coordinate-system / titleless-button issues) but are
    /// kept as fallbacks. The readback gate (`newlyMountedSlot` matches the exact
    /// `plugin_id`) is the safety net: a wrong variant fails closed as
    /// `post_insert_plugin_mismatch` + rollback, never a false State A.
    private static let resultSelectionStrategies: [ResultSelectionStrategy] = [
        ResultSelectionStrategy(name: "return_only") { _, _, _ in
            AXMouseHelper.pressReturn()
        },
        ResultSelectionStrategy(name: "row_double_click") { _, firstRow, runtime in
            doubleClickElementCenter(firstRow, runtime: runtime)
        },
        ResultSelectionStrategy(name: "add_button_press") { dialog, _, runtime in
            if let button = addButton(in: dialog, runtime: runtime) {
                _ = AXHelpers.performAction(button, kAXPressAction as String, runtime: runtime)
            }
        },
        ResultSelectionStrategy(name: "row_click_then_add_button") { dialog, firstRow, runtime in
            clickElementCenter(firstRow, runtime: runtime)
            if let button = addButton(in: dialog, runtime: runtime) {
                _ = AXHelpers.performAction(button, kAXPressAction as String, runtime: runtime)
            }
        },
    ]

    /// The dialog's add button: the AXButton with a press action and no title
    /// (R12 — the '추가'/Add button surfaces no title). Prefers a button that is
    /// NOT inside the results outline so we don't press a disclosure triangle.
    private static func addButton(in dialog: AXUIElement, runtime: AXHelpers.Runtime) -> AXUIElement? {
        let buttons = AXHelpers.findAllDescendants(
            of: dialog, role: kAXButtonRole as String, maxDepth: 6, runtime: runtime
        )
        // A titled button is more likely the intended add/commit control; else
        // fall back to the first untitled button.
        if let titled = buttons.first(where: {
            let t = AXHelpers.getTitle($0, runtime: runtime)
            return t != nil && !(t!.isEmpty)
        }) {
            return titled
        }
        return buttons.first
    }

    /// Post a native CGEvent double-click at the screen centre of an AX element
    /// (uses its real `AXPosition`/`AXSize`; the results row exposes a normal
    /// frame, unlike the insert-popup leaf).
    private static func doubleClickElementCenter(_ element: AXUIElement, runtime: AXHelpers.Runtime) {
        guard let center = elementCenter(element, runtime: runtime) else { return }
        AXMouseHelper.doubleClick(at: center)
    }

    private static func clickElementCenter(_ element: AXUIElement, runtime: AXHelpers.Runtime) {
        guard let center = elementCenter(element, runtime: runtime) else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        if let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: center, mouseButton: .left),
           let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: center, mouseButton: .left) {
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }

    /// Screen centre of an element, or nil when its frame is degenerate (the
    /// R12 frameless-leaf failure mode: a (0, screen-bottom) / zero-size rect is
    /// rejected so we never misclick at the screen corner).
    private static func elementCenter(_ element: AXUIElement, runtime: AXHelpers.Runtime) -> CGPoint? {
        guard let pos = AXHelpers.getPosition(element, runtime: runtime),
              let size = AXHelpers.getSize(element, runtime: runtime),
              size.width > 1, size.height > 1 else { return nil }
        return CGPoint(x: pos.x + size.width / 2, y: pos.y + size.height / 2)
    }

    /// One readable, occupied insert slot observed during a strip inventory pass:
    /// physical slot index → (canonical plugin id, display name).
    private struct InventoryEntry: Sendable {
        let pluginID: String?
        let name: String?
    }

    /// Snapshot the target strip's FULL occupied-slot inventory: physical slot
    /// index → observed (plugin id, name). Reuses the drift-safe enumerator and
    /// the same observed-name → canonical-id mapping as `get_inventory`, so the
    /// readback diff is identical to the inventory view. Returns nil when the
    /// mixer/strip subtree is unreadable. Only readable-occupied slots are keyed;
    /// empty and occupied-unreadable slots are omitted (a diff cares only about a
    /// newly-readable plugin appearing).
    private static func fullStripInventory(
        track: Int, runtime: AXLogicProElements.Runtime
    ) -> [Int: InventoryEntry]? {
        guard let mixer = AXLogicProElements.getMixerArea(runtime: runtime) else { return nil }
        let strips = AXLogicProElements.mixerChannelStrips(in: mixer, runtime: runtime.ax)
        guard track < strips.count else { return nil }
        let slots = AXLogicProElements.audioPluginInsertSlots(in: strips[track], runtime: runtime.ax)
        var result: [Int: InventoryEntry] = [:]
        for slot in slots where slot.readStatus == .occupiedReadable {
            let name = slot.name
            result[slot.index] = InventoryEntry(
                pluginID: name.flatMap(VerifiedPluginCatalog.pluginID(forObservedName:)),
                name: name
            )
        }
        return result
    }

    /// Poll `fullStripInventory` until it is readable or the timeout elapses
    /// (Logic commits the insert asynchronously). Returns the first readable
    /// snapshot, or nil if the strip stayed unreadable for the whole window.
    private static func pollFullStripInventory(
        track: Int, runtime: AXLogicProElements.Runtime, timeoutMs: Int
    ) async -> [Int: InventoryEntry]? {
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
        repeat {
            if let inv = fullStripInventory(track: track, runtime: runtime) {
                return inv
            }
            try? await Task.sleep(for: .milliseconds(120))
        } while Date() < deadline
        return nil
    }

    /// Result of a CONDITION-based inventory poll (P1-2). `satisfied` is the last
    /// readable snapshot for which `condition` held (the settled state we waited
    /// for); when the deadline passes without the condition ever holding, returns
    /// the last readable snapshot (if any) so the caller can diagnose what it saw.
    private struct ConditionPollResult: Sendable {
        let satisfied: [Int: InventoryEntry]?   // non-nil only when condition held
        let lastReadable: [Int: InventoryEntry]?
    }

    /// Poll `fullStripInventory` until `condition` holds on a readable snapshot or
    /// the timeout elapses (P1-2: do NOT settle on the first merely-readable read —
    /// Logic commits/undoes asynchronously, so a fixed-sleep "first readable"
    /// could observe the pre-change state and drive a false-fail on insert or an
    /// extra Undo on rollback that eats a prior user action). The condition is the
    /// settled state the caller is waiting for (e.g. "the new plugin appeared" /
    /// "the stray slot is empty").
    private static func pollStripInventoryUntil(
        track: Int,
        runtime: AXLogicProElements.Runtime,
        timeoutMs: Int,
        condition: ([Int: InventoryEntry]) -> Bool
    ) async -> ConditionPollResult {
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
        var lastReadable: [Int: InventoryEntry]? = nil
        repeat {
            if let inv = fullStripInventory(track: track, runtime: runtime) {
                lastReadable = inv
                if condition(inv) {
                    return ConditionPollResult(satisfied: inv, lastReadable: inv)
                }
            }
            try? await Task.sleep(for: .milliseconds(120))
        } while Date() < deadline
        return ConditionPollResult(satisfied: nil, lastReadable: lastReadable)
    }

    /// Find the slot where `pluginID` is NEWLY present (occupied-readable in
    /// `post` with that id, but not already in `pre` with the same id). This is
    /// the freshly-mounted target regardless of which physical slot Logic chose.
    /// Returns the lowest such slot for determinism.
    private static func newlyMountedSlot(
        pluginID: String, pre: [Int: InventoryEntry], post: [Int: InventoryEntry]
    ) -> (slot: Int, name: String?)? {
        let candidates = post
            .filter { $0.value.pluginID == pluginID && pre[$0.key]?.pluginID != pluginID }
            .sorted { $0.key < $1.key }
        guard let first = candidates.first else { return nil }
        return (first.key, first.value.name)
    }

    /// Find any slot where SOME plugin newly appeared — used to detect+roll back a
    /// stray mount of a non-requested plugin. P1-1: detect by SLOT-PRESENCE (a slot
    /// readable-occupied in `post` but NOT in `pre`) OR by a changed display name
    /// at an already-occupied slot. The previous id-only diff missed a
    /// non-allowlisted stray (its `plugin_id` resolves to nil, so `nil != nil` was
    /// false). Carries the observed display `name` so the rollback can confirm
    /// removal even when the canonical id is nil. Returns the lowest such slot.
    private static func newlyMountedAnyPlugin(
        pre: [Int: InventoryEntry], post: [Int: InventoryEntry]
    ) -> (slot: Int, pluginID: String?, name: String?)? {
        let changed = post
            .filter { (slot, entry) in
                guard let priorEntry = pre[slot] else { return true }  // newly occupied
                // Same slot already occupied before — changed iff id or name differs.
                return priorEntry.pluginID != entry.pluginID || priorEntry.name != entry.name
            }
            .sorted { $0.key < $1.key }
        guard let first = changed.first else { return nil }
        return (first.key, first.value.pluginID, first.value.name)
    }

    /// Close a leftover "위치로 이동" / "Go to Position" floating dialog (a prior
    /// AX side effect) so it cannot steal focus / keep the Mix menu disabled.
    /// Best-effort via AppleScript: click its cancel/close button if present.
    /// Returns whether a dialog was found and dismissed.
    @discardableResult
    private static func closeGoToPositionDialog() async -> Bool {
        let script = """
        tell application "System Events"
            tell process "Logic Pro"
                set didClose to false
                repeat with w in (every window whose name contains "위치" or name contains "Go to Position")
                    try
                        set didClose to true
                        if (exists button "취소" of w) then
                            click button "취소" of w
                        else if (exists button "Cancel" of w) then
                            click button "Cancel" of w
                        else
                            try
                                click (first button of w whose subrole is "AXCloseButton")
                            end try
                        end if
                    end try
                end repeat
                if didClose then
                    return "ok"
                else
                    return "missing"
                end if
            end tell
        end tell
        """
        let result = await AppleScriptChannel.executeAppleScript(script)
        let text = AppleScriptChannel.appleScriptResultText(from: result)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "missing"
        return text == "ok"
    }

    /// Honest outcome of a verified rollback attempt.
    struct RollbackResult: Sendable {
        let attempted: Bool
        let succeeded: Bool
        let retries: Int
        let lastClickResult: String
    }

    /// Live per-attempt undo action: hide plug-in windows (so the undo lands on
    /// the global Edit menu, not a focused plugin window that would swallow it)
    /// then click the Edit-menu undo item by localized prefix. Returns the click
    /// result's raw string ("ok"/"disabled"/"missing").
    static let liveUndoClick: @Sendable () async -> String = {
        _ = await hideAllPluginWindows()
        return await clickEditUndoViaAppleScript().rawValue
    }

    /// Removal-confirmation tristate for a readback snapshot: true (verified
    /// gone), false (verified still present), nil (cannot determine → never claim
    /// success). Identifies the stray by exact (slot, id), then (id only), then
    /// (slot + observed name), then (slot only); both-unknown is unverifiable.
    private static func strayRemovalConfirmed(
        in inv: [Int: InventoryEntry],
        strayPluginID: String?, straySlot: Int?, strayName: String?
    ) -> Bool? {
        if let straySlot, let strayPluginID {
            return inv[straySlot]?.pluginID != strayPluginID
        }
        if let strayPluginID {
            return !inv.values.contains { $0.pluginID == strayPluginID }
        }
        if let straySlot {
            // Known slot, nil id (non-allowlisted stray): confirmed gone iff the
            // slot is empty, OR — if it is occupied again — its display name no
            // longer matches the stray's name (P1-1: name-based confirmation).
            guard let entry = inv[straySlot] else { return true }
            if let strayName { return entry.name != strayName }
            return false  // slot still occupied, no name to disambiguate
        }
        return nil  // both unknown → unverifiable
    }

    /// Roll back a stray plugin insert and CONFIRM removal by CONDITION-based
    /// readback. R16 live: the old click-only undo reported `ok` but the plugin
    /// persisted. P1-2 safety: this clicks Edit-menu Undo at most ONCE per
    /// confirmed-still-present state, then condition-polls for the stray to leave
    /// — it never re-clicks Undo on an ambiguous/mid-settle snapshot (a blind
    /// retry could undo a PRIOR user action and corrupt real data). A retry's
    /// next Undo only fires when the stray is still DEFINITIVELY present.
    ///
    /// `undoClick` is the injectable per-attempt undo action (hide plug-in windows
    /// + click Edit-menu undo), returning "ok"/"disabled"/"missing". Production
    /// wires the live AppleScript; tests inject a canned result so the honesty-
    /// critical removal-confirmation is exercised hermetically.
    static func verifiedUndoPluginInsert(
        track: Int,
        strayPluginID: String?,
        straySlot: Int?,
        strayName: String? = nil,
        runtime: AXLogicProElements.Runtime,
        maxRetries: Int = 4,
        undoClick: @Sendable () async -> String = liveUndoClick
    ) async -> RollbackResult {
        var attempted = false
        var lastClick = "missing"
        for attempt in 0..<maxRetries {
            let clickRaw = await undoClick()
            lastClick = clickRaw
            if clickRaw == "ok" { attempted = true }

            // CONDITION-poll for the stray to leave (P1-2): wait until a readable
            // snapshot CONFIRMS removal, rather than settling on the first readable
            // (mid-settle) snapshot. Success only on a confirmed-gone snapshot.
            let poll = await pollStripInventoryUntil(
                track: track, runtime: runtime, timeoutMs: 1_500
            ) { inv in
                strayRemovalConfirmed(
                    in: inv, strayPluginID: strayPluginID, straySlot: straySlot, strayName: strayName
                ) == true
            }
            if poll.satisfied != nil {
                return RollbackResult(
                    attempted: attempted, succeeded: true,
                    retries: attempt, lastClickResult: lastClick
                )
            }

            // Removal not confirmed within the window. Only retry the Undo when the
            // last readable snapshot shows the stray DEFINITIVELY STILL PRESENT
            // (confirmed == false). An unverifiable (nil) or unreadable snapshot
            // must NOT trigger another Undo — a blind retry risks undoing a prior
            // user action (P1-2 data-safety). Also stop if the menu had nothing to
            // undo / was missing.
            let stillDefinitelyPresent = poll.lastReadable.map { inv in
                strayRemovalConfirmed(
                    in: inv, strayPluginID: strayPluginID, straySlot: straySlot, strayName: strayName
                ) == false
            } ?? false
            if !stillDefinitelyPresent || clickRaw == "disabled" || clickRaw == "missing" {
                break
            }
        }
        return RollbackResult(
            attempted: attempted, succeeded: false,
            retries: maxRetries, lastClickResult: lastClick
        )
    }

    // MARK: - Helpers

    /// Insertable stock plugins (R5/R7) — Noise Gate is identity-only, excluded.
    static let insertableAllowlist: Set<String> = [
        "logic.stock.effect.gain",
        "logic.stock.effect.channel_eq",
        "logic.stock.effect.compressor",
    ]

    private static func invalidParamsStateC(_ operation: String, _ detail: String) -> String {
        HonestContract.encodeV2StateC(
            error: .invalidParams,
            extras: [
                "operation": operation,
                "what_was_attempted": "validate request parameters",
                "what_was_observed": detail,
                "safe_to_retry": false,
                "write_attempted": false,
            ]
        )
    }

    private static func resolvedIdentity(track: Int, insert: Int, pluginID: String) -> [String: Any] {
        [
            "track_index": track,
            "insert": insert,
            "plugin_id": pluginID,
        ]
    }
}

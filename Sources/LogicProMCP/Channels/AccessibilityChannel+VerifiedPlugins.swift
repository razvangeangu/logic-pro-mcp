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
///   - `plugin.insert_verified` — validation gates only (schema/mode/path/
///     inventory-complete/slot-occupied). The live AX insert (fail-closed State C
///     per R7) is T6; T3 fails closed at the live-write boundary rather than
///     emitting the legacy `insert_plugin` State B through the verified surface.
///
/// NOTE: no live AX parameter write/readback (State A) is implemented here. Any
/// path that would require it fails closed with a terminal HC v2 State C.
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

    // MARK: - insert_verified (validation gates only; AC5/AC17/AC19)

    /// Guarded verified insert entry. T3 implements the write-preceding gates:
    /// schema → mode → project path → inventory `complete:true` → `slot_occupied`.
    /// The live AX insert + fail-closed post-insert readback (R7) is T6; T3 fails
    /// closed at the live-write boundary rather than routing through the legacy
    /// `defaultInsertPlugin` (which would leak a v1 State B through the verified
    /// surface).
    static func defaultInsertVerified(
        params: [String: String],
        runtime: AXLogicProElements.Runtime = .production,
        frontDocumentPath: FrontDocumentPathProvider = liveFrontDocumentPath
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

        // Step 5 — inventory must be complete + slot must be verified-empty
        // before an insert is even considered (R3/R7, AC5).
        guard let mixer = AXLogicProElements.getMixerArea(runtime: runtime) else {
            return .error(HonestContract.encodeV2StateC(
                error: .incompleteInventory,
                extras: [
                    "operation": operation,
                    "target_identity": resolvedIdentity(track: track, insert: insert, pluginID: pluginID),
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
                    "target_identity": resolvedIdentity(track: track, insert: insert, pluginID: pluginID),
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
                    "target_identity": resolvedIdentity(track: track, insert: insert, pluginID: pluginID),
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
                    "target_identity": resolvedIdentity(track: track, insert: insert, pluginID: pluginID),
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
                    "target_identity": resolvedIdentity(track: track, insert: insert, pluginID: pluginID),
                    "existing_plugin_name": slots[insert].name ?? NSNull(),
                    "existing_read_status": slots[insert].readStatus.rawValue,
                    "what_was_attempted": "insert \(pluginID) into slot \(insert)",
                    "what_was_observed": "slot \(insert) is occupied (read_status=\(slots[insert].readStatus.rawValue))",
                    "safe_to_retry": false,
                    "write_attempted": false,
                ]
            ))
        }

        // T3 live-write boundary: all deterministic gates passed, but the live
        // AX insert + fail-closed post-insert readback is T6 (requires T0
        // evidence). Fail closed rather than fabricate a State A or leak the
        // legacy `insert_plugin` v1 State B. `not_implemented` is the honest
        // terminal code — no live write is attempted, so `write_attempted:false`
        // is truthful (unlike a code that implies an attempted UI action).
        return .error(HonestContract.encodeV2StateC(
            error: .notImplemented,
            extras: [
                "operation": operation,
                "target_identity": resolvedIdentity(track: track, insert: insert, pluginID: pluginID),
                "what_was_attempted": "perform the verified AX insert of \(pluginID) into slot \(insert)",
                "what_was_observed": "the live verified insert path is not enabled in this build (pending T0 evidence + T6)",
                "safe_to_retry": false,
                "write_attempted": false,
            ]
        ))
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

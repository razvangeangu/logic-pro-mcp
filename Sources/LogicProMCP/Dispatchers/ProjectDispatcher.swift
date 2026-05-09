import Foundation
import MCP

struct ProjectDispatcher {
    struct LifecycleExecution: Sendable {
        let executionError: String?
        let timedOut: Bool
        let terminationStatus: Int32
        let stderrOutput: String
    }

    static let tool = commandTool(
        name: "logic_project",
        description: "Project lifecycle + read-only project state in Logic Pro. Commands: new, open, save, save_as, close, bounce, launch, quit, get_regions. Params: open -> { path: String }; save_as -> { path: String }; close -> { saving?: \"yes\"|\"no\"|\"ask\" }; bounce/launch/quit -> {}; get_regions -> {} (returns JSON array of { name, trackIndex, startBar, endBar, kind, rawHelp } parsed from Logic's arrange area via AX); others -> {}.",
        commandDescription: "Project command to execute"
    )

    static func handle(
        command: String,
        params: [String: Value],
        router: ChannelRouter,
        cache: StateCache,
        // Single source of truth — use ProcessUtils.isLogicProRunning everywhere
        // (NSRunningApplication-based with multi-fallback). Removed prior OR with
        // PermissionChecker.checkAutomationState() == .granted because permission
        // grant ≠ Logic actually running, and the OR caused state inconsistency
        // vs `system.health` and `transport.toggle_cycle` which use ProcessUtils only.
        isLogicProRunning: () -> Bool = { ProcessUtils.isLogicProRunning },
        executeLifecycleScript: (String) async -> LifecycleExecution = { script in
            await executeAppleScript(script)
        },
        sleep: (UInt64) async -> Void = { try? await Task.sleep(nanoseconds: $0) }
    ) async -> CallTool.Result {
        let confirmed = boolParam(params, "confirmed", default: false)

        // H-1 (2026-05-08 enterprise review): pre-fix this dispatcher logged
        // `[AUDIT] project.<command> executed` BEFORE param validation,
        // BEFORE the destructive-confirmation gate, and BEFORE the route
        // actually fired. Enterprise audit trails treated rejected calls
        // (e.g. `project.open` with empty path) as if they had run, which
        // both inflated the audit volume and hid genuine failures behind
        // identical log lines.
        //
        // The fix splits the audit signal into three distinct phases that
        // a SIEM can filter on:
        //   - `rejected` — validation refused the call before any side effect
        //   - `confirmation_required` — destructive policy returned the
        //     confirmation envelope; no route was attempted
        //   - `executed` — the underlying route was invoked (success or
        //     hard failure) and any side effect has either landed or been
        //     reported back from the channel
        //
        // Helpers below are intentionally inlined per-case rather than
        // wrapped in a single function so the log is always paired with
        // the immediately-following return — refactors that move the
        // return without moving the audit call would surface as a diff
        // anomaly during review.

        switch command {
        case "new":
            audit(command, phase: .executed)
            let result = await router.route(operation: "project.new")
            // v3.1.2 (P0-3) — clear cache on lifecycle success so the next
            // resource read / name-based routing decision sees the fresh
            // project's tracks instead of the previous project's stale list.
            // Without this, `cache.getTracks()` returned 38 tracks for over
            // a minute after `project.new` (live-witnessed); the StatePoller
            // takes up to 3s to overwrite, and resource consumers assumed
            // the data was current. clearProjectState() is idempotent and
            // mutation-free on actor state — safe to call on every success
            // even if the poller would have caught up eventually.
            await invalidateOnSuccess(result, cache: cache)
            return toolTextResult(result)

        case "open":
            let path = stringParam(params, "path")
            guard !path.isEmpty else {
                audit(command, phase: .rejected, reason: "missing path")
                return toolTextResult("open requires 'path' param", isError: true)
            }
            guard AppleScriptSafety.isValidProjectPath(path, requireExisting: true) else {
                audit(command, phase: .rejected, reason: "invalid path")
                return toolTextResult("open requires an existing absolute .logicx project path", isError: true)
            }
            if !confirmed, let response = DestructivePolicy.confirmationResponse(command: command) {
                audit(command, phase: .confirmationRequired)
                return toolTextResult(response)
            }
            audit(command, phase: .executed)
            let result = await router.route(
                operation: "project.open",
                params: ["path": path]
            )
            // v3.1.2 (P0-3) — same cache stale-after-lifecycle bug as `new`.
            await invalidateOnSuccess(result, cache: cache)
            return toolTextResult(result)

        case "save":
            audit(command, phase: .executed)
            let result = await router.route(operation: "project.save")
            return toolTextResult(result)

        case "save_as":
            let path = stringParam(params, "path")
            guard !path.isEmpty else {
                audit(command, phase: .rejected, reason: "missing path")
                return toolTextResult("save_as requires 'path' param", isError: true)
            }
            guard AppleScriptSafety.isValidProjectPath(path, requireExisting: false) else {
                audit(command, phase: .rejected, reason: "invalid path")
                return toolTextResult("save_as requires an absolute .logicx project path", isError: true)
            }
            if !confirmed, let response = DestructivePolicy.confirmationResponse(command: command) {
                audit(command, phase: .confirmationRequired)
                return toolTextResult(response)
            }
            audit(command, phase: .executed)
            let result = await router.route(
                operation: "project.save_as",
                params: ["path": path]
            )
            return toolTextResult(result)

        case "close":
            let savingRaw = stringParam(params, "saving", default: "yes")
            let saving = ["yes", "no", "ask"].contains(savingRaw) ? savingRaw : "yes"
            if savingRaw != saving {
                audit(command, phase: .rejected, reason: "invalid saving value")
                return toolTextResult(
                    "close 'saving' must be one of: yes, no, ask (got: \(savingRaw))",
                    isError: true
                )
            }
            if !confirmed, let response = DestructivePolicy.confirmationResponse(command: command) {
                audit(command, phase: .confirmationRequired)
                return toolTextResult(response)
            }
            audit(command, phase: .executed)
            let result = await router.route(
                operation: "project.close",
                params: ["saving": saving]
            )
            // v3.1.2 (P0-3) — closing the project leaves the cache stuffed
            // with the just-closed tracks/regions/markers. Clear so resource
            // reads honestly reflect "no project" until the next open.
            await invalidateOnSuccess(result, cache: cache)
            return toolTextResult(result)

        case "bounce":
            if !confirmed, let response = DestructivePolicy.confirmationResponse(command: command) {
                audit(command, phase: .confirmationRequired)
                return toolTextResult(response)
            }
            audit(command, phase: .executed)
            let result = await router.route(operation: "project.bounce")
            return toolTextResult(result)

        case "is_running":
            return toolTextResult(isLogicProRunning() ? "true" : "false")

        case "get_regions":
            // Read-only arrange-area inspection. Necessary for programmatic
            // verification of record_sequence region placement — without this
            // the only feedback loop was visual screenshots.
            let result = await router.route(operation: "region.get_regions")
            return toolTextResult(result)

        case "launch":
            if isLogicProRunning() {
                audit(command, phase: .rejected, reason: "already running")
                return toolTextResult("Logic Pro is already running")
            }
            audit(command, phase: .executed)
            return await runLifecycleScript(
                script: "tell application \"Logic Pro\" to activate",
                successMessage: "Logic Pro launched",
                expectedRunning: true,
                actionLabel: "launch",
                execute: executeLifecycleScript,
                isLogicProRunning: isLogicProRunning,
                sleep: sleep
            )

        case "quit":
            if !confirmed, let response = DestructivePolicy.confirmationResponse(command: command) {
                audit(command, phase: .confirmationRequired)
                return toolTextResult(response)
            }
            if !isLogicProRunning() {
                audit(command, phase: .rejected, reason: "not running")
                return toolTextResult("Logic Pro is not running")
            }
            audit(command, phase: .executed)
            return await runLifecycleScript(
                script: "tell application \"Logic Pro\" to quit",
                successMessage: "Logic Pro quit",
                expectedRunning: false,
                actionLabel: "quit",
                execute: executeLifecycleScript,
                isLogicProRunning: isLogicProRunning,
                sleep: sleep
            )

        default:
            return toolTextResult(
                "Unknown project command: \(command). Available: new, open, save, save_as, close, bounce, is_running, launch, quit, get_regions",
                isError: true
            )
        }
    }

    /// v3.1.2 (P0-3) — invalidate cache on successful project lifecycle
    /// transition (`new` / `open` / `close`). Defensive: only fires when the
    /// underlying channel reports success, so a failed AppleScript leaves
    /// the cache untouched (preserves whatever truth the poller had).
    private static func invalidateOnSuccess(_ result: ChannelResult, cache: StateCache) async {
        guard result.isSuccess else { return }
        await cache.clearProjectState()
    }

    /// H-1 (2026-05-08 enterprise review): audit phases for L1+ project
    /// commands. Splits the prior single `executed` line into three signals
    /// a SIEM can filter on.
    ///
    /// **Contract — v3.4.1 (Boomer P2-3):** `executed` is emitted
    /// **immediately before** `router.route(...)` fires, not after. This
    /// records *invocation intent* rather than *outcome*. The reasons:
    ///   - Outcome lives in the channel response (success / hard error).
    ///   - A post-route audit line would be lost if the AppleScript hung
    ///     or the actor died, exactly when audit visibility matters most.
    ///   - SIEM consumers that want the outcome can correlate the
    ///     `executed` line with the channel response by timestamp +
    ///     command name; the contract gives them both signals.
    /// Concretely: an L1 command that passes validation but fails at the
    /// channel level (Logic not running, AppleScript denied) will still
    /// show `[AUDIT] project.<command> executed` followed by an error
    /// envelope on the wire. That is the intended behaviour.
    enum AuditPhase: String, Sendable {
        /// Validation refused the call before any side effect.
        case rejected
        /// Destructive policy returned the confirmation envelope; no route
        /// was attempted, the caller is expected to retry with `confirmed:true`.
        case confirmationRequired = "confirmation_required"
        /// The underlying route was invoked. Success or hard failure is then
        /// captured in the channel response, not the audit line.
        case executed
    }

    /// Emit an audit line for L1+ commands. No-op for L0 (`is_running`,
    /// `get_regions`, etc.) so read-only ops don't pollute the audit log.
    static func audit(_ command: String, phase: AuditPhase, reason: String? = nil) {
        guard DestructivePolicy.needsAuditLog(for: command) else { return }
        if let reason {
            Log.info("[AUDIT] project.\(command) \(phase.rawValue) — \(reason)", subsystem: "project")
        } else {
            Log.info("[AUDIT] project.\(command) \(phase.rawValue)", subsystem: "project")
        }
    }

    private static func runLifecycleScript(
        script: String,
        successMessage: String,
        expectedRunning: Bool,
        actionLabel: String,
        execute: (String) async -> LifecycleExecution,
        isLogicProRunning: () -> Bool,
        sleep: (UInt64) async -> Void
    ) async -> CallTool.Result {
        let execution = await execute(script)
        if let executionError = execution.executionError {
            return toolTextResult("Failed to \(actionLabel) Logic Pro: \(executionError)", isError: true)
        }
        if execution.timedOut {
            return toolTextResult(
                "Failed to \(actionLabel) Logic Pro: timed out after \(Int(ServerConfig.appleScriptTimeout))s",
                isError: true
            )
        }
        if execution.terminationStatus != 0 {
            let message = execution.stderrOutput.isEmpty
                ? "osascript exited with status \(execution.terminationStatus)"
                : execution.stderrOutput
            return toolTextResult("Failed to \(actionLabel) Logic Pro: \(message)", isError: true)
        }

        let statePolls = Int(max(1, ServerConfig.appleScriptTimeout * 10))
        for _ in 0..<statePolls {
            if isLogicProRunning() == expectedRunning {
                return toolTextResult(successMessage)
            }
            await sleep(100_000_000)
        }

        return toolTextResult(
            "Lifecycle command completed but Logic Pro did not reach expected running state",
            isError: true
        )
    }

    static func executeAppleScript(
        _ script: String,
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/osascript")
    ) async -> LifecycleExecution {
        let process = Process()
        let stderr = Pipe()
        process.executableURL = executableURL
        process.arguments = ["-e", script]
        process.standardError = stderr
        // Don't hold a second Pipe for stdout — osascript output isn't read here.
        process.standardOutput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return LifecycleExecution(
                executionError: String(describing: error),
                timedOut: false,
                terminationStatus: -1,
                stderrOutput: ""
            )
        }

        let timeoutNs = UInt64(ServerConfig.appleScriptTimeout * 1_000_000_000)
        let pollIntervalNs: UInt64 = 50_000_000
        var waitedNs: UInt64 = 0

        while process.isRunning && waitedNs < timeoutNs {
            try? await Task.sleep(nanoseconds: pollIntervalNs)
            waitedNs += pollIntervalNs
        }

        if process.isRunning {
            process.terminate()
            // Reap zombie so the stderr Pipe's file descriptors are released
            // promptly — same class of FD leak that killed the server under
            // sustained set_tempo stress (diagnosed via BrokenPipeError).
            process.waitUntilExit()
            return LifecycleExecution(
                executionError: nil,
                timedOut: true,
                terminationStatus: process.terminationStatus,
                stderrOutput: ""
            )
        }

        let stderrOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Release Pipe FDs explicitly — delayed deinit was a leak vector under
        // sustained stress (same root cause as sprint 51 MCP server crash).
        try? stderr.fileHandleForReading.close()
        try? stderr.fileHandleForWriting.close()
        return LifecycleExecution(
            executionError: nil,
            timedOut: false,
            terminationStatus: process.terminationStatus,
            stderrOutput: stderrOutput
        )
    }
}

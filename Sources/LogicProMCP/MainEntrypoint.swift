import Dispatch
import Foundation

protocol ServerStarting: Sendable {
    func start() async throws
    func stop() async
}

extension ServerStarting {
    /// Default no-op so existing test mocks that only implement `start()` keep
    /// working. Production `LogicProServer` overrides with the real teardown.
    func stop() async {}
}

extension LogicProServer: ServerStarting {}

enum MainEntrypoint {
    static func run(
        arguments: [String],
        permissionCheck: () -> PermissionChecker.PermissionStatus = PermissionChecker.check,
        serverFactory: () -> any ServerStarting = { LogicProServer() },
        approvalStoreFactory: () -> any ManualValidationStoring = { ManualValidationStore() },
        doctorRuntime: SetupDoctor.Runtime = .production,
        lifecycleRuntime: SetupLifecycle.Runtime = .production,
        writeStdout: (String) -> Void = { message in
            FileHandle.standardOutput.write(Data(message.utf8))
        },
        writeStderr: (String) -> Void = { message in
            FileHandle.standardError.write(Data(message.utf8))
        }
    ) async -> Int {
        let approvalStore = approvalStoreFactory()

        if isDoctorCommand(arguments) {
            let report = SetupDoctor.generate(
                arguments: arguments,
                permissionStatus: permissionCheck(),
                approvals: await approvalStore.list(),
                runtime: doctorRuntime
            )
            let output = arguments.contains("--json")
                ? encodeJSON(report)
                : SetupDoctor.renderHuman(report)
            writeStdout(output + "\n")
            return SetupDoctor.shouldExitWithFailure(report) ? 1 : 0
        }

        if let command = lifecycleCommand(arguments) {
            // Live execution is intentionally NOT performed here — it is delegated
            // to Scripts/install.sh / uninstall.sh. Without --dry-run we refuse
            // honestly and exit non-zero rather than faking execution.
            guard arguments.contains("--dry-run") else {
                let script = command == .uninstall
                    ? "Scripts/uninstall.sh"
                    : "Scripts/install.sh"
                writeStderr(
                    "Live \(command.rawValue) is not performed by this binary. "
                        + "Re-run with --dry-run to preview the plan, or run \(script) "
                        + "to execute (see docs/SETUP.md).\n"
                )
                return 1
            }
            let plan = SetupLifecycle.plan(command: command, runtime: lifecycleRuntime)
            let output = arguments.contains("--json")
                ? encodeJSON(plan)
                : SetupLifecycle.renderHuman(plan)
            writeStdout(output + "\n")
            return 0
        }

        if arguments.contains("--list-approvals") {
            let approvals = await approvalStore.list()
            writeStderr(ManualValidationStore.summary(for: approvals) + "\n")
            return 0
        }

        if let rawChannel = optionValue("--approve-channel", in: arguments) {
            guard let channel = ManualValidationChannel.parse(rawChannel) else {
                writeStderr("Unknown approval channel: \(rawChannel)\n")
                return 1
            }
            do {
                try await approvalStore.approve(channel, note: optionValue("--approval-note", in: arguments))
                writeStderr("Approved \(channel.rawValue) for runtime use.\n")
                return 0
            } catch {
                writeStderr("Failed to persist approval for \(channel.rawValue): \(error)\n")
                return 1
            }
        }

        if let rawChannel = optionValue("--revoke-channel", in: arguments) {
            guard let channel = ManualValidationChannel.parse(rawChannel) else {
                writeStderr("Unknown approval channel: \(rawChannel)\n")
                return 1
            }
            do {
                try await approvalStore.revoke(channel)
                writeStderr("Revoked approval for \(channel.rawValue).\n")
                return 0
            } catch {
                writeStderr("Failed to revoke approval for \(channel.rawValue): \(error)\n")
                return 1
            }
        }

        if arguments.contains("--check-permissions") {
            let status = permissionCheck()
            writeStderr(status.summary + "\n")
            return status.allGranted ? 0 : 1
        }

        let server = serverFactory()

        // SIGTERM / SIGINT → coordinated shutdown, then exit. Pre-fix the
        // handlers called `exit(0)` directly which skipped the AX poller,
        // channel transports, and virtual MIDI port teardown — leaking
        // resources every time a supervisor restarted the process.
        //
        // The handler runs on a dedicated background queue (not `.main`) so
        // `group.wait` cannot deadlock against an actor that needs the main
        // runloop. Hard timeout caps cleanup at 3s; on overrun we still exit
        // with a non-zero code so a supervisor can notice.
        let signalQueue = DispatchQueue(label: "logic-pro-mcp.signal")
        let signalSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: signalQueue)
        let intSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: signalQueue)
        signal(SIGTERM, SIG_IGN)
        signal(SIGINT, SIG_IGN)

        let shutdownTimeout = DispatchTimeInterval.seconds(3)
        let shutdown: @Sendable () -> Void = { [server] in
            let group = DispatchGroup()
            group.enter()
            Task {
                await server.stop()
                group.leave()
            }
            if group.wait(timeout: .now() + shutdownTimeout) == .timedOut {
                Log.error(
                    "Shutdown timeout exceeded — exiting without confirmed cleanup",
                    subsystem: "main"
                )
                exit(1)
            }
            Log.info("Server stopped — graceful shutdown complete", subsystem: "main")
            exit(0)
        }
        signalSource.setEventHandler(handler: shutdown)
        intSource.setEventHandler(handler: shutdown)
        signalSource.resume()
        intSource.resume()

        do {
            try await server.start()
            return 0
        } catch {
            Log.error("Server failed: \(error)", subsystem: "main")
            return 1
        }
    }

    private static func optionValue(_ option: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: option), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func isDoctorCommand(_ arguments: [String]) -> Bool {
        Array(arguments.dropFirst()).first == "doctor"
    }

    private static func lifecycleCommand(_ arguments: [String]) -> SetupLifecycle.Command? {
        guard let first = Array(arguments.dropFirst()).first else { return nil }
        return SetupLifecycle.Command(rawValue: first)
    }
}

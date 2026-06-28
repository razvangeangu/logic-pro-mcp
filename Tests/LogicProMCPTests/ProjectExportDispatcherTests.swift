import Foundation
import Testing
@testable import LogicProMCP

@Suite("Project export dispatcher integration")
struct ProjectExportDispatcherTests {
    @Test("dispatcher export_run returns HC-truthful isError on a failed run")
    func dispatcherExportRunIsErrorOnFailure() async throws {
        let projDir = try makeExecTempDir()
        let outputRoot = try makeExecTempDir()
        let project = try makeLogicxProject(in: projDir, named: "Dispatch Song")

        let router = await makeExportRouter()
        let options = fastOptions(identity: { "/Users/elsewhere/Wrong.logicx" })
        let cache = StateCache()

        let result = await ProjectDispatcher.handle(
            command: "export_run",
            params: [
                "projects": .array([.string(project.path)]),
                "output_root": .string(outputRoot.path),
                "artifacts": .array([.string("bounce")]),
                "confirmed": .bool(true),
            ],
            router: router,
            cache: cache,
            exportOptions: options
        )

        #expect(try #require(result.isError))
        let text = sharedToolText(result)
        #expect(text.contains("\"schema\":\"logic_pro_mcp_export_run.v1\""))
        #expect(text.contains("\"status\":\"failed\""))
    }

    @Test("dispatcher export_run rejects invalid params before any execution")
    func dispatcherExportRunRejectsInvalidParams() async throws {
        let router = await makeExportRouter()
        let cache = StateCache()
        let options = fastOptions(identity: { nil })

        let result = await ProjectDispatcher.handle(
            command: "export_run",
            params: [
                "projects": .array([.string("/tmp/nope.logicx")]),
                "confirmed": .bool(true),
            ],
            router: router,
            cache: cache,
            exportOptions: options
        )

        #expect(try #require(result.isError))
        #expect(sharedToolText(result).contains("invalid_params"))
    }

    @Test("dispatcher export_run returns confirmation_required HC envelope when confirmed omitted")
    func dispatcherExportRunConfirmationRequired() async throws {
        let projDir = try makeExecTempDir()
        let outputRoot = try makeExecTempDir()
        let project = try makeLogicxProject(in: projDir, named: "Gate Song")

        let router = await makeExportRouter()
        let options = fastOptions(identity: { project.path })
        let cache = StateCache()

        let result = await ProjectDispatcher.handle(
            command: "export_run",
            params: [
                "projects": .array([.string(project.path)]),
                "output_root": .string(outputRoot.path),
                "artifacts": .array([.string("bounce")]),
            ],
            router: router,
            cache: cache,
            exportOptions: options
        )

        #expect(try #require(result.isError))
        let text = sharedToolText(result)
        #expect(text.contains("\"status\":\"confirmation_required\""))
        #expect(text.contains("\"confirmed\":false"))
    }
}

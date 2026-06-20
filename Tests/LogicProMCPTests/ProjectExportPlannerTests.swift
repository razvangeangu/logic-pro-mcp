import Foundation
import MCP
import Testing
@testable import LogicProMCP

private func makeExportPlannerDirectory(_ name: String = UUID().uuidString) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func makeExportPlannerProject(named name: String = "Planner Song") throws -> URL {
    let url = try makeExportPlannerDirectory()
        .appendingPathComponent(name)
        .appendingPathExtension("logicx")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite("Project export planner")
struct ProjectExportPlannerTests {
    @Test("builds a dry-run export manifest without executing workflow steps")
    func dryRunManifestPlan() throws {
        let project = try makeExportPlannerProject(named: "Planner Song")
        let outputRoot = try makeExportPlannerDirectory()

        let plan = try ProjectExportPlanner.plan(params: [
            "projects": .array([.string(project.path)]),
            "output_root": .string(outputRoot.path),
            "artifacts": .array([.string("stem"), .string("bounce")]),
        ])

        #expect(plan.schema == "logic_pro_mcp_export_manifest.v1")
        #expect(plan.status == "planned")
        #expect(plan.executionMode == "dry_run_only")
        #expect(plan.projectCount == 1)
        #expect(plan.projects.first?.validationStatus == "valid")
        #expect(plan.projects.first?.manifestStatus == "pending")
        #expect(plan.requiredConfirmations.contains { $0.level == "L2" })
        #expect(plan.unsupportedOrBlockedSteps.map(\.operation).contains("export_run"))
        #expect(plan.baselineVerification.contains("artifact_exists"))
        #expect(plan.baselineVerification.contains("no_silent_overwrite"))

        let artifacts = try #require(plan.projects.first?.expectedArtifacts)
        #expect(artifacts.map(\.kind) == ["bounce", "stem"])
        let firstArtifact = try #require(artifacts.first)
        #expect(firstArtifact.path.hasSuffix("/Planner-Song-bounce.wav"))
        #expect(artifacts.allSatisfy { $0.verification.pathUnderOutputRoot })
        #expect(artifacts.allSatisfy { $0.status == "pending" })

        let steps = try #require(plan.projects.first?.workflowSteps)
        #expect(steps.allSatisfy { !$0.executed })
        #expect(steps.allSatisfy { $0.requiresConfirmationLevel == "L2" })
        #expect(steps.map(\.command) == ["open", "bounce", "close"])
    }

    @Test("reports collision and zero-byte artifact risks without mutating files")
    func collisionAndZeroByteRisks() throws {
        let project = try makeExportPlannerProject(named: "Collision Song")
        let outputRoot = try makeExportPlannerDirectory()
        let existingArtifact = outputRoot.appendingPathComponent("Collision-Song-bounce.wav")
        try Data().write(to: existingArtifact)

        let plan = try ProjectExportPlanner.plan(params: [
            "project": .string(project.path),
            "output_root": .string(outputRoot.path),
            "artifact": .string("bounce"),
        ])

        let artifact = try #require(plan.projects.first?.expectedArtifacts.first)
        #expect(plan.status == "degraded")
        #expect(artifact.status == "existing")
        #expect(artifact.verification.exists)
        #expect(artifact.verification.fileSizeBytes == 0)
        #expect(artifact.verification.wouldOverwrite)
        #expect(artifact.verification.issues.contains("artifact_would_overwrite"))
        #expect(artifact.verification.issues.contains("artifact_zero_bytes"))
    }

    @Test("rejects invalid parameter shapes before producing a plan")
    func rejectsInvalidParams() {
        #expect(throws: ExportPlanError.self) {
            _ = try ProjectExportPlanner.plan(params: [
                "project": .string("/tmp/Nope.logicx"),
                "output_root": .string("relative/out"),
            ])
        }
        #expect(throws: ExportPlanError.self) {
            _ = try ProjectExportPlanner.plan(params: [
                "project": .string("/tmp/Nope.logicx"),
                "output_root": .string("/tmp/out"),
                "artifacts": .array([.string("cloud_upload")]),
            ])
        }
        #expect(throws: ExportPlanError.self) {
            _ = try ProjectExportPlanner.plan(params: [
                "projects": .array([]),
                "output_root": .string("/tmp/out"),
            ])
        }
    }

    @Test("dispatcher returns manifest JSON and never routes channels")
    func dispatcherDoesNotRoute() async throws {
        let project = try makeExportPlannerProject(named: "Dispatcher Song")
        let outputRoot = try makeExportPlannerDirectory()
        let router = ChannelRouter()
        let keyCmd = MockChannel(id: .midiKeyCommands)
        let appleScript = MockChannel(id: .appleScript)
        await router.register(keyCmd)
        await router.register(appleScript)

        let result = await ProjectDispatcher.handle(
            command: "export_plan",
            params: [
                "projects": .array([.string(project.path)]),
                "output_root": .string(outputRoot.path),
            ],
            router: router,
            cache: StateCache()
        )

        #expect(result.isError != true)
        let data = try #require(sharedToolText(result).data(using: .utf8))
        let plan = try JSONDecoder().decode(ProjectExportPlan.self, from: data)
        #expect(plan.schema == ProjectExportPlanner.schema)
        #expect(plan.executionMode == "dry_run_only")
        #expect(await keyCmd.executedOps.isEmpty)
        #expect(await appleScript.executedOps.isEmpty)
    }
}

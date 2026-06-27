import Foundation
import MCP
import Testing
@testable import LogicProMCP

private func makePlannerVariantDirectory(_ name: String = UUID().uuidString) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func makePlannerVariantProject(named name: String = "Planner Variant Song") throws -> URL {
    let url = try makePlannerVariantDirectory()
        .appendingPathComponent(name)
        .appendingPathExtension("logicx")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite("Project export planner variant artifacts")
struct ProjectExportPlannerArtifactVariantTests {
    @Test("fail_if_exists treats a same-stem different-extension artifact as an existing overwrite risk")
    func failIfExistsBlocksExistingVariantExtension() throws {
        let project = try makePlannerVariantProject(named: "Variant Song")
        let outputRoot = try makePlannerVariantDirectory()
        let existingVariant = outputRoot.appendingPathComponent("Variant-Song-bounce.aif")
        try Data("existing-aif".utf8).write(to: existingVariant)

        let plan = try ProjectExportPlanner.plan(params: [
            "project": .string(project.path),
            "output_root": .string(outputRoot.path),
            "artifact": .string("bounce"),
        ])

        let artifact = try #require(plan.projects.first?.expectedArtifacts.first)
        #expect(artifact.status == "existing")
        #expect(artifact.verification.exists)
        #expect(artifact.verification.wouldOverwrite)
        #expect(artifact.verification.issues.contains("artifact_would_overwrite"))
    }

    @Test("fail_if_exists ignores same-stem non-audio sidecars")
    func failIfExistsIgnoresNonAudioSidecars() throws {
        let project = try makePlannerVariantProject(named: "Variant Song")
        let outputRoot = try makePlannerVariantDirectory()
        let sidecar = outputRoot.appendingPathComponent("Variant-Song-bounce.json")
        try Data("{\"note\":\"metadata\"}".utf8).write(to: sidecar)

        let plan = try ProjectExportPlanner.plan(params: [
            "project": .string(project.path),
            "output_root": .string(outputRoot.path),
            "artifact": .string("bounce"),
        ])

        let artifact = try #require(plan.projects.first?.expectedArtifacts.first)
        #expect(artifact.status == "pending")
        #expect(!artifact.verification.exists)
        #expect(!artifact.verification.wouldOverwrite)
        #expect(!artifact.verification.issues.contains("artifact_would_overwrite"))
    }

    @Test("fail_if_exists treats case-only different same-stem artifacts as overwrite risks")
    func failIfExistsBlocksCaseOnlyVariantExtension() throws {
        let project = try makePlannerVariantProject(named: "Variant Song")
        let outputRoot = try makePlannerVariantDirectory()
        let existingVariant = outputRoot.appendingPathComponent("variant-song-bounce.aif")
        try Data("existing-aif".utf8).write(to: existingVariant)

        let plan = try ProjectExportPlanner.plan(params: [
            "project": .string(project.path),
            "output_root": .string(outputRoot.path),
            "artifact": .string("bounce"),
        ])

        let artifact = try #require(plan.projects.first?.expectedArtifacts.first)
        #expect(artifact.status == "existing")
        #expect(artifact.verification.exists)
        #expect(artifact.verification.wouldOverwrite)
        #expect(artifact.verification.issues.contains("artifact_would_overwrite"))
    }
}

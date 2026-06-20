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

/// FileManager whose `fileExists` behaves normally (so the artifact reports
/// exists=true) but whose attribute read always fails — reproduces the
/// TOCTOU / unreadable case PR99-C3 must report as "size unknown", not "0 bytes".
private final class UnreadableAttributesFileManager: FileManager {
    override func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        throw CocoaError(.fileReadUnknown)
    }
}

@Suite("Project export planner")
struct ProjectExportPlannerTests {
    @Test("builds a dry-run export manifest without executing workflow steps")
    func dryRunManifestPlan() throws {
        let project = try makeExportPlannerProject(named: "Planner Song")
        let outputRoot = try makeExportPlannerDirectory()

        // PR99-T2: snapshot the output dir to prove the dry run mutates no files,
        // rather than trusting the hardcoded `executed: false` flag.
        let before = Set(try FileManager.default.contentsOfDirectory(atPath: outputRoot.path))

        let plan = try ProjectExportPlanner.plan(params: [
            "projects": .array([.string(project.path)]),
            "output_root": .string(outputRoot.path),
            "artifacts": .array([.string("stem"), .string("bounce")]),
        ])

        let after = Set(try FileManager.default.contentsOfDirectory(atPath: outputRoot.path))
        #expect(before == after)

        #expect(plan.schema == "logic_pro_mcp_export_manifest.v1")
        #expect(plan.status == "planned")
        #expect(plan.executionMode == "dry_run_only")
        #expect(plan.projectCount == 1)
        #expect(plan.projects.first?.validationStatus == "valid")
        #expect(plan.projects.first?.manifestStatus == "pending")
        // C3: run-window anchor is present and non-empty so the advertised
        // mtime_within_run_window gate has something to bound against.
        #expect(!plan.generatedAt.isEmpty)
        #expect(plan.baselineVerification.contains("mtime_within_run_window"))
        // C1: open/bounce confirm at L2, close confirms at L3 (canonical policy).
        let l2 = try #require(plan.requiredConfirmations.first { $0.level == "L2" })
        #expect(l2.requiredFor.contains("open"))
        #expect(l2.requiredFor.contains("bounce"))
        #expect(!l2.requiredFor.contains("close"))
        let l3 = try #require(plan.requiredConfirmations.first { $0.level == "L3" })
        #expect(l3.requiredFor.contains("close"))
        #expect(!l3.requiredFor.contains("open"))
        #expect(plan.unsupportedOrBlockedSteps.map(\.operation).contains("export_run"))
        #expect(plan.baselineVerification.contains("artifact_exists"))
        #expect(plan.baselineVerification.contains("no_silent_overwrite"))

        let artifacts = try #require(plan.projects.first?.expectedArtifacts)
        #expect(artifacts.map(\.kind) == ["bounce", "stem"])
        let firstArtifact = try #require(artifacts.first)
        #expect(firstArtifact.path.hasSuffix("/Planner-Song-bounce.wav"))
        #expect(artifacts.allSatisfy { $0.verification.pathUnderOutputRoot })
        #expect(artifacts.allSatisfy { $0.status == "pending" })
        // PR99-T2: no .wav was actually written for the planned artifact.
        #expect(!FileManager.default.fileExists(atPath: firstArtifact.path))

        let steps = try #require(plan.projects.first?.workflowSteps)
        #expect(steps.allSatisfy { !$0.executed })
        // C1: per-command confirmation level — open/bounce L2, close L3.
        let openStep = try #require(steps.first { $0.command == "open" })
        let bounceStep = try #require(steps.first { $0.command == "bounce" })
        let closeStep = try #require(steps.first { $0.command == "close" })
        #expect(openStep.requiresConfirmationLevel == "L2")
        #expect(bounceStep.requiresConfirmationLevel == "L2")
        #expect(closeStep.requiresConfirmationLevel == "L3")
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

        let before = Set(try FileManager.default.contentsOfDirectory(atPath: outputRoot.path))
        let result = await ProjectDispatcher.handle(
            command: "export_plan",
            params: [
                "projects": .array([.string(project.path)]),
                "output_root": .string(outputRoot.path),
            ],
            router: router,
            cache: StateCache()
        )
        let after = Set(try FileManager.default.contentsOfDirectory(atPath: outputRoot.path))
        #expect(before == after)

        #expect(result.isError != true)
        let data = try #require(sharedToolText(result).data(using: .utf8))
        let plan = try JSONDecoder().decode(ProjectExportPlan.self, from: data)
        #expect(plan.schema == ProjectExportPlanner.schema)
        #expect(plan.executionMode == "dry_run_only")
        #expect(await keyCmd.executedOps.isEmpty)
        #expect(await appleScript.executedOps.isEmpty)
    }

    // MARK: - PR99-T5: multi-project batch enumeration

    @Test("plans every project in a batch with distinct per-project indices and namespaced step ids")
    func multiProjectBatchPlan() throws {
        let alpha = try makeExportPlannerProject(named: "Alpha Song")
        let beta = try makeExportPlannerProject(named: "Beta Song")
        let outputRoot = try makeExportPlannerDirectory()

        let plan = try ProjectExportPlanner.plan(params: [
            "projects": .array([.string(alpha.path), .string(beta.path)]),
            "output_root": .string(outputRoot.path),
            "artifacts": .array([.string("bounce")]),
        ])

        #expect(plan.projectCount == 2)
        #expect(plan.projects.count == 2)
        let p0 = try #require(plan.projects.first)
        let p1 = try #require(plan.projects.last)
        #expect(p0.index == 0)
        #expect(p1.index == 1)
        #expect(p0.displayName == "Alpha Song")
        #expect(p1.displayName == "Beta Song")
        #expect(p0.projectPath == alpha.path)
        #expect(p1.projectPath == beta.path)
        #expect(p0.workflowSteps.map(\.id) == ["project_0_open", "project_0_export", "project_0_close"])
        #expect(p1.workflowSteps.map(\.id) == ["project_1_open", "project_1_export", "project_1_close"])
        let allIDs = (p0.workflowSteps + p1.workflowSteps).map(\.id)
        #expect(Set(allIDs).count == allIDs.count)
        #expect(try #require(p0.expectedArtifacts.first).path.hasSuffix("/Alpha-Song-bounce.wav"))
        #expect(try #require(p1.expectedArtifacts.first).path.hasSuffix("/Beta-Song-bounce.wav"))
        // distinct basenames -> no collision flag
        #expect(!(try #require(p0.expectedArtifacts.first)).verification.issues.contains("artifact_path_collides_in_plan"))
    }

    // MARK: - PR99-C1 / edge-2 / edge-3: intra-plan artifact-path collisions

    @Test("two projects with the same basename in different dirs collide and degrade the plan")
    func sameBasenameCrossProjectCollision() throws {
        let dirA = try makeExportPlannerDirectory()
        let dirB = try makeExportPlannerDirectory()
        let songA = dirA.appendingPathComponent("Song").appendingPathExtension("logicx")
        let songB = dirB.appendingPathComponent("Song").appendingPathExtension("logicx")
        try FileManager.default.createDirectory(at: songA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: songB, withIntermediateDirectories: true)
        let outputRoot = try makeExportPlannerDirectory()

        let plan = try ProjectExportPlanner.plan(params: [
            "projects": .array([.string(songA.path), .string(songB.path)]),
            "output_root": .string(outputRoot.path),
            "artifacts": .array([.string("bounce")]),
        ])

        #expect(plan.status == "degraded")
        let a0 = try #require(plan.projects.first?.expectedArtifacts.first)
        let a1 = try #require(plan.projects.last?.expectedArtifacts.first)
        #expect(a0.verification.issues.contains("artifact_path_collides_in_plan"))
        #expect(a1.verification.issues.contains("artifact_path_collides_in_plan"))
    }

    @Test("case-only-different basenames collide on the case-insensitive default volume")
    func caseInsensitiveCrossProjectCollision() throws {
        let dirA = try makeExportPlannerDirectory()
        let dirB = try makeExportPlannerDirectory()
        let songA = dirA.appendingPathComponent("Song").appendingPathExtension("logicx")
        let songB = dirB.appendingPathComponent("song").appendingPathExtension("logicx")
        try FileManager.default.createDirectory(at: songA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: songB, withIntermediateDirectories: true)
        let outputRoot = try makeExportPlannerDirectory()

        let plan = try ProjectExportPlanner.plan(params: [
            "projects": .array([.string(songA.path), .string(songB.path)]),
            "output_root": .string(outputRoot.path),
            "artifacts": .array([.string("bounce")]),
        ])

        #expect(plan.status == "degraded")
        let a0 = try #require(plan.projects.first?.expectedArtifacts.first)
        let a1 = try #require(plan.projects.last?.expectedArtifacts.first)
        #expect(a0.verification.issues.contains("artifact_path_collides_in_plan"))
        #expect(a1.verification.issues.contains("artifact_path_collides_in_plan"))
    }

    @Test("the same project listed twice collides with itself and degrades the plan")
    func duplicateProjectEntryCollision() throws {
        let project = try makeExportPlannerProject(named: "Dup Song")
        let outputRoot = try makeExportPlannerDirectory()

        let plan = try ProjectExportPlanner.plan(params: [
            "projects": .array([.string(project.path), .string(project.path)]),
            "output_root": .string(outputRoot.path),
            "artifacts": .array([.string("bounce")]),
        ])

        #expect(plan.status == "degraded")
        #expect(plan.projects.allSatisfy { project in
            project.expectedArtifacts.allSatisfy {
                $0.verification.issues.contains("artifact_path_collides_in_plan")
            }
        })
    }

    // MARK: - PR99-C3: zero-byte vs unreadable disambiguation

    @Test("an existing artifact whose attributes are unreadable is flagged unreadable, not zero-byte")
    func unreadableArtifactSizeIsNotZeroByte() throws {
        let project = try makeExportPlannerProject(named: "Unreadable Song")
        let outputRoot = try makeExportPlannerDirectory()
        // A real on-disk file the artifact resolves to. `fileExists` will see it,
        // but the injected FileManager refuses to read its attributes — this is the
        // TOCTOU / unreadable case PR99-C3 must distinguish from a genuine 0 bytes.
        let existing = outputRoot.appendingPathComponent("Unreadable-Song-bounce.wav")
        try Data("non-empty".utf8).write(to: existing)

        let plan = try ProjectExportPlanner.plan(
            params: [
                "project": .string(project.path),
                "output_root": .string(outputRoot.path),
                "artifact": .string("bounce"),
            ],
            fileManager: UnreadableAttributesFileManager()
        )

        let artifact = try #require(plan.projects.first?.expectedArtifacts.first)
        #expect(artifact.verification.exists)
        #expect(artifact.verification.fileSizeBytes == nil)
        #expect(artifact.verification.issues.contains("artifact_size_unreadable"))
        #expect(!artifact.verification.issues.contains("artifact_zero_bytes"))
    }

    // MARK: - PR99-T1: skip_existing collision policy

    @Test("skip_existing suppresses overwrite flagging for a pre-existing artifact")
    func skipExistingCollisionPolicy() throws {
        let project = try makeExportPlannerProject(named: "Skip Song")
        let outputRoot = try makeExportPlannerDirectory()
        let existing = outputRoot.appendingPathComponent("Skip-Song-bounce.wav")
        try Data("non-empty".utf8).write(to: existing)

        let plan = try ProjectExportPlanner.plan(params: [
            "project": .string(project.path),
            "output_root": .string(outputRoot.path),
            "artifact": .string("bounce"),
            "collision_policy": .string("skip_existing"),
        ])
        let artifact = try #require(plan.projects.first?.expectedArtifacts.first)
        #expect(artifact.verification.exists)
        #expect(!artifact.verification.wouldOverwrite)
        #expect(!artifact.verification.issues.contains("artifact_would_overwrite"))
        #expect(plan.collisionPolicy == "skip_existing")
        #expect(plan.status == "planned")
    }

    @Test("invalid collision_policy is rejected")
    func invalidCollisionPolicyRejected() {
        #expect(throws: ExportPlanError.self) {
            _ = try ProjectExportPlanner.plan(params: [
                "project": .string("/tmp/Nope.logicx"),
                "output_root": .string("/tmp/out"),
                "collision_policy": .string("overwrite"),
            ])
        }
    }

    // MARK: - PR99-T3: run_id contract

    @Test("run_id is deterministic, prefixed, and input-sensitive")
    func runIDContractIsStable() throws {
        let project = try makeExportPlannerProject(named: "RunID Song")
        let outputRoot = try makeExportPlannerDirectory()
        let params: [String: Value] = [
            "projects": .array([.string(project.path)]),
            "output_root": .string(outputRoot.path),
            "artifacts": .array([.string("stem"), .string("bounce")]),
        ]

        let a = try ProjectExportPlanner.plan(params: params)
        let b = try ProjectExportPlanner.plan(params: params)
        #expect(a.runID.hasPrefix("export-"))
        #expect(a.runID.count > "export-".count)
        #expect(a.runID == b.runID)

        let otherRoot = try makeExportPlannerDirectory()
        let c = try ProjectExportPlanner.plan(params: [
            "projects": .array([.string(project.path)]),
            "output_root": .string(otherRoot.path),
            "artifacts": .array([.string("stem"), .string("bounce")]),
        ])
        #expect(c.runID != a.runID)

        let otherProject = try makeExportPlannerProject(named: "Other Song")
        let d = try ProjectExportPlanner.plan(params: [
            "projects": .array([.string(otherProject.path)]),
            "output_root": .string(outputRoot.path),
            "artifacts": .array([.string("stem"), .string("bounce")]),
        ])
        #expect(d.runID != a.runID)
    }

    // MARK: - PR99-T4: valid-shaped but missing project

    @Test("missing but well-formed project path degrades the plan without throwing")
    func missingProjectDegradesPlan() throws {
        let outputRoot = try makeExportPlannerDirectory()
        let missing = outputRoot.appendingPathComponent("Missing-Song.logicx").path

        let plan = try ProjectExportPlanner.plan(params: [
            "project": .string(missing),
            "output_root": .string(outputRoot.path),
            "artifact": .string("bounce"),
        ])

        #expect(plan.status == "degraded")
        let project = try #require(plan.projects.first)
        #expect(project.validationStatus == "invalid")
        #expect(project.validationIssues.contains("project_path_not_found"))
        #expect(!project.validationIssues.contains("project_path_must_be_absolute_logicx"))
    }

    // MARK: - PR99-T6: dispatcher fail-closed

    @Test("dispatcher fails closed on invalid export_plan params")
    func dispatcherFailsClosedOnInvalidParams() async throws {
        let router = ChannelRouter()
        let keyCmd = MockChannel(id: .midiKeyCommands)
        await router.register(keyCmd)

        let result = await ProjectDispatcher.handle(
            command: "export_plan",
            params: [
                "projects": .array([.string("/tmp/Nope.logicx")]),
                "output_root": .string("relative/out"),
            ],
            router: router,
            cache: StateCache()
        )

        #expect(result.isError!)
        #expect(sharedToolText(result).contains("invalid_params"))
        #expect(await keyCmd.executedOps.isEmpty)
    }

    @Test("dispatcher fails closed on empty projects array")
    func dispatcherFailsClosedOnEmptyProjects() async throws {
        let router = ChannelRouter()
        let keyCmd = MockChannel(id: .midiKeyCommands)
        await router.register(keyCmd)

        let result = await ProjectDispatcher.handle(
            command: "export_plan",
            params: [
                "projects": .array([]),
                "output_root": .string("/tmp/out"),
            ],
            router: router,
            cache: StateCache()
        )

        #expect(result.isError!)
        #expect(sharedToolText(result).contains("invalid_params"))
        #expect(await keyCmd.executedOps.isEmpty)
    }

    // MARK: - PR99-T7: non-empty existing artifact (zero-byte vs would-overwrite)

    @Test("non-empty existing artifact flags overwrite but not zero-byte and reports true size")
    func nonEmptyExistingArtifactRisk() throws {
        let project = try makeExportPlannerProject(named: "NonEmpty Song")
        let outputRoot = try makeExportPlannerDirectory()
        let existingArtifact = outputRoot.appendingPathComponent("NonEmpty-Song-bounce.wav")
        try Data([0x01, 0x02]).write(to: existingArtifact)

        let plan = try ProjectExportPlanner.plan(params: [
            "project": .string(project.path),
            "output_root": .string(outputRoot.path),
            "artifact": .string("bounce"),
        ])

        let artifact = try #require(plan.projects.first?.expectedArtifacts.first)
        #expect(artifact.verification.exists)
        #expect(artifact.verification.fileSizeBytes == 2)
        #expect(artifact.verification.wouldOverwrite)
        #expect(artifact.verification.issues.contains("artifact_would_overwrite"))
        #expect(!artifact.verification.issues.contains("artifact_zero_bytes"))
        #expect(!artifact.verification.issues.contains("artifact_size_unreadable"))
    }

    // MARK: - PR99-edge-1: single project param is trimmed like the array branch

    @Test("single project param is trimmed so it matches the array branch normalization")
    func singleProjectParamIsTrimmed() throws {
        let project = try makeExportPlannerProject(named: "Trim Song")
        let outputRoot = try makeExportPlannerDirectory()

        let trimmed = try ProjectExportPlanner.plan(params: [
            "project": .string(project.path),
            "output_root": .string(outputRoot.path),
            "artifact": .string("bounce"),
        ])
        let padded = try ProjectExportPlanner.plan(params: [
            "project": .string("  \(project.path)  "),
            "output_root": .string(outputRoot.path),
            "artifact": .string("bounce"),
        ])

        #expect(trimmed.projects.first?.projectPath == project.path)
        #expect(padded.projects.first?.projectPath == project.path)
        // identical normalization -> identical deterministic run id
        #expect(trimmed.runID == padded.runID)
        #expect(padded.projects.first?.validationStatus == "valid")
    }

    // MARK: - PR99-edge-4: output_root system-location containment

    @Test("output_root resolving to a system location via traversal is rejected")
    func outputRootSystemTraversalRejected() {
        #expect(throws: ExportPlanError.self) {
            _ = try ProjectExportPlanner.plan(params: [
                "project": .string("/tmp/Nope.logicx"),
                "output_root": .string("/Users/x/../../etc/out"),
            ])
        }
    }
}

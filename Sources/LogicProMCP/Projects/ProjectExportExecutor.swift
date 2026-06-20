import Foundation
import MCP

/// Issue #27 Phase 2 — GUARDED EXECUTION of the export plan that Phase 1
/// (#99, `export_plan`) only described as a dry run.
///
/// The executor re-runs `ProjectExportPlanner` to obtain the authoritative
/// manifest (so the contract a caller reviewed in `export_plan` is the contract
/// that executes), then walks each project artifact through a fail-closed state
/// machine:
///
///   1. `confirmed == true` is mandatory — otherwise NOTHING is opened, bounced,
///      or written, and the run reports `confirmation_required` (State-C-shaped:
///      `success:false`).
///   2. Artifacts the plan reported as already present + verifiable on disk are
///      SKIPPED (idempotent — this is what makes `export_resume` resumable).
///   3. For every artifact that still needs producing: open the project,
///      read back the OBSERVED front-document identity and require it to match
///      the planned project path (fail closed on mismatch — never bounce the
///      wrong project), trigger the bounce, poll (bounded) for the artifact file
///      to appear, then verify it with `AudioAnalyzer` (exists + non-zero +
///      non-silent + sane duration).
///   4. Honest Contract per artifact:
///        State A — bounce fired AND on-disk verification PASSED.
///        State B — bounce fired but the artifact could not be verified
///                  (never appeared / analyzer warn/fail) — success uncertain.
///        State C — a hard failure (open/identity/bounce route error, or the
///                  plan itself was degraded for this artifact).
///   5. The collision policy from the plan is honoured: under `fail_if_exists`
///      an artifact the plan flagged `would_overwrite` is NEVER overwritten —
///      it fails closed (State C) instead of bouncing over an existing file.
///
/// Every live side effect (open / bounce / close) and every readback
/// (front-document identity, audio analysis, file polling) goes through an
/// injectable seam, so the state machine, the resume/idempotency logic, and the
/// fail-closed gates are fully unit-testable with fake channels, an injected
/// `FileManager`, fixture WAV files, and a stub identity provider — no live
/// Logic required to test the logic.
enum ProjectExportExecutor {
    static let schema = "logic_pro_mcp_export_run.v1"

    /// Bounded poll budget for an artifact file to appear after a bounce fires.
    /// Injectable via `Options` so tests don't actually sleep.
    static let defaultPollAttempts = 60
    static let defaultPollIntervalNanos: UInt64 = 500_000_000

    // MARK: - Injectable seams

    /// Reads the OBSERVED front-document project path from live Logic. Mirrors
    /// the verified-plugin identity gate seam (`FrontDocumentPathProvider`) so
    /// the readback authority is the same one the open/save lifecycle relies on.
    /// Returns nil when no front document can be read.
    typealias IdentityReadback = @Sendable () async -> String?

    /// Analyze an on-disk artifact. Defaults to `AudioAnalyzer.analyzeFile`; the
    /// `policy` carries the output-root containment + non-silence/duration gates.
    typealias ArtifactAnalyzer = @Sendable (_ path: String, _ policy: AudioAnalyzer.AnalysisPolicy) -> AudioAnalyzer.Result

    /// Drives a real path-directed bounce and returns the produced on-disk path
    /// (nil on failure). Logic Pro has NO AppleScript bounce/export verb and its
    /// bounce save panel is not Accessibility-addressable, so the live default
    /// shells out to `Scripts/logic_bounce.py` (cliclick/CGEvent UI automation).
    /// `name` is the artifact basename without extension; `outputDir` is where the
    /// produced file must land. When nil (unit tests / no live Logic), `produce`
    /// falls back to the router-bounce + poll-planned-path seam.
    typealias BounceToPath = @Sendable (_ name: String, _ outputDir: String) async -> String?

    /// `@unchecked Sendable` mirrors `AudioAnalyzer.Runtime`: the only
    /// non-Sendable member is `FileManager`, which Apple documents as safe to
    /// share across threads for the read-only `fileExists` use here.
    struct Options: @unchecked Sendable {
        var identityReadback: IdentityReadback
        var analyze: ArtifactAnalyzer
        var fileManager: FileManager
        var pollAttempts: Int
        var pollIntervalNanos: UInt64
        var sleep: @Sendable (UInt64) async -> Void
        /// Minimum sane duration (seconds) for a produced artifact. A bounce that
        /// yields a sub-tick file is treated as not-verified (State B).
        var minimumDurationSeconds: Double
        /// Live path-directed bounce. nil keeps the legacy router-bounce seam so
        /// the deterministic unit tests never shell out to the UI helper.
        var bounceToPath: BounceToPath?

        static func live() -> Options {
            Options(
                identityReadback: { await AppleScriptChannel.currentDocumentPath() },
                analyze: { path, policy in AudioAnalyzer.analyzeFile(path: path, policy: policy) },
                fileManager: .default,
                pollAttempts: defaultPollAttempts,
                pollIntervalNanos: defaultPollIntervalNanos,
                sleep: { try? await Task.sleep(nanoseconds: $0) },
                minimumDurationSeconds: 0.05,
                bounceToPath: { name, dir in await ProjectExportExecutor.runBounceHelper(name: name, outputDir: dir) }
            )
        }
    }

    /// Invoke the cliclick-based bounce helper and return the produced artifact
    /// path. Resolves the helper via `LOGIC_PRO_MCP_BOUNCE_HELPER` or the
    /// repo-relative `Scripts/logic_bounce.py`. Returns nil on any failure.
    static func runBounceHelper(name: String, outputDir: String) async -> String? {
        let env = ProcessInfo.processInfo.environment
        let helper = env["LOGIC_PRO_MCP_BOUNCE_HELPER"]
            ?? FileManager.default.currentDirectoryPath + "/Scripts/logic_bounce.py"
        guard FileManager.default.fileExists(atPath: helper) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", helper, "--name", name, "--output-dir", outputDir]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ok = obj["success"] as? Bool, ok,
              let artifact = obj["artifact"] as? String else {
            return nil
        }
        return artifact
    }

    // MARK: - Result model (logic_pro_mcp_export_run.v1)

    struct RunResult: Codable, Sendable, Equatable {
        let schema: String
        let runID: String
        let mode: String
        let confirmed: Bool
        let status: String
        let outputRoot: String
        let collisionPolicy: String
        let projectCount: Int
        let artifactsTotal: Int
        let artifactsVerified: Int
        let artifactsSkipped: Int
        let artifactsUncertain: Int
        let artifactsFailed: Int
        let projects: [RunProject]
        let nextSafeAction: String

        enum CodingKeys: String, CodingKey {
            case schema
            case runID = "run_id"
            case mode
            case confirmed
            case status
            case outputRoot = "output_root"
            case collisionPolicy = "collision_policy"
            case projectCount = "project_count"
            case artifactsTotal = "artifacts_total"
            case artifactsVerified = "artifacts_verified"
            case artifactsSkipped = "artifacts_skipped"
            case artifactsUncertain = "artifacts_uncertain"
            case artifactsFailed = "artifacts_failed"
            case projects
            case nextSafeAction = "next_safe_action"
        }
    }

    struct RunProject: Codable, Sendable, Equatable {
        let index: Int
        let projectPath: String
        let displayName: String
        let observedProjectPath: String?
        let identityVerified: Bool
        let opened: Bool
        let artifacts: [RunArtifact]

        enum CodingKeys: String, CodingKey {
            case index
            case projectPath = "project_path"
            case displayName = "display_name"
            case observedProjectPath = "observed_project_path"
            case identityVerified = "identity_verified"
            case opened
            case artifacts
        }
    }

    /// Per-artifact Honest Contract outcome. `state` is "A"|"B"|"C"; `verified`
    /// is true ONLY for State A (on-disk verification passed). `error` is present
    /// for State C, `reason` for State B.
    struct RunArtifact: Codable, Sendable, Equatable {
        let kind: String
        let path: String
        let state: String
        let verified: Bool
        let bounceFired: Bool
        let error: String?
        let reason: String?
        let evidence: ArtifactEvidence?

        enum CodingKeys: String, CodingKey {
            case kind
            case path
            case state
            case verified
            case bounceFired = "bounce_fired"
            case error
            case reason
            case evidence
        }
    }

    /// On-disk verification evidence captured at State A (and recorded for State
    /// B so a caller can see HOW close the artifact was to verifiable). Mirrors
    /// the analyzer fields a future resume keys off.
    struct ArtifactEvidence: Codable, Sendable, Equatable {
        let exists: Bool
        let fileSizeBytes: Int64
        let durationSeconds: Double
        let sampleRate: Int
        let channelCount: Int
        let silenceRatio: Double
        let peakDbfs: Double
        let verificationStatus: String
        let verificationReasons: [String]
        let source: String

        enum CodingKeys: String, CodingKey {
            case exists
            case fileSizeBytes = "file_size_bytes"
            case durationSeconds = "duration_seconds"
            case sampleRate = "sample_rate"
            case channelCount = "channel_count"
            case silenceRatio = "silence_ratio"
            case peakDbfs = "peak_dbfs"
            case verificationStatus = "verification_status"
            case verificationReasons = "verification_reasons"
            case source
        }

        init(from analysis: AudioAnalyzer.Result, source: String) {
            self.exists = analysis.exists
            self.fileSizeBytes = analysis.fileSizeBytes
            self.durationSeconds = analysis.durationSeconds
            self.sampleRate = analysis.sampleRate
            self.channelCount = analysis.channelCount
            self.silenceRatio = analysis.silenceRatio
            self.peakDbfs = analysis.peakDbfs
            self.verificationStatus = analysis.verification.status.rawValue
            self.verificationReasons = analysis.verification.reasons
            self.source = source
        }
    }

    // MARK: - Entry point

    /// Execute (or resume) the guarded export. `resume` only changes the
    /// surfaced `mode` string and `next_safe_action` wording — the artifact
    /// state machine is identical: both skip already-present+verified artifacts
    /// and produce the rest. That shared path is what makes `export_run`
    /// re-entrant and `export_resume` idempotent.
    static func run(
        params: [String: Value],
        router: ChannelRouter,
        resume: Bool,
        options: Options
    ) async -> RunResult {
        // (1) Re-run the planner. Caller-facing param errors are surfaced by the
        // dispatcher's planner call BEFORE this executor is reached, so a throw
        // here is unexpected — fail closed with an empty, failed run rather than
        // crash.
        let plan: ProjectExportPlan
        do {
            plan = try ProjectExportPlanner.plan(params: params, fileManager: options.fileManager)
        } catch {
            return failedRun(
                runID: "export-unplanned",
                mode: resume ? "resume" : "run",
                confirmed: false,
                outputRoot: stringParam(params, "output_root", "outputRoot"),
                collisionPolicy: stringParam(params, "collision_policy", default: "fail_if_exists"),
                reason: "plan_failed: \(error)"
            )
        }

        // (2) confirmed gate — fail closed before ANY mutation.
        let confirmed: Bool
        switch strictBoolParam(params, "confirmed") {
        case .value(let value):
            confirmed = value
        case .missing, .invalid:
            confirmed = false
        }
        guard confirmed else {
            return confirmationRequiredRun(plan: plan, resume: resume)
        }

        var runProjects: [RunProject] = []
        for project in plan.projects {
            let runProject = await execute(
                project: project,
                plan: plan,
                router: router,
                options: options
            )
            runProjects.append(runProject)
        }

        return aggregate(plan: plan, resume: resume, projects: runProjects)
    }

    // MARK: - Per-project execution

    private static func execute(
        project: ProjectExportPlanProject,
        plan: ProjectExportPlan,
        router: ChannelRouter,
        options: Options
    ) async -> RunProject {
        // Partition: artifacts already present+verified are skipped without any
        // mutation (resume idempotency). Everything else needs the project open.
        var pendingExists = false
        for artifact in project.expectedArtifacts where artifactNeedsProduction(artifact, plan: plan) {
            pendingExists = true
            break
        }

        // A degraded/invalid project (bad path, intra-plan collision, would-
        // overwrite under fail_if_exists) never gets opened — every artifact
        // fails closed with the plan's own reason.
        guard project.validationStatus == "valid" else {
            let arts = project.expectedArtifacts.map { artifact in
                failedArtifact(artifact, error: "project_invalid: \(project.validationIssues.joined(separator: ","))")
            }
            return RunProject(
                index: project.index,
                projectPath: project.projectPath,
                displayName: project.displayName,
                observedProjectPath: nil,
                identityVerified: false,
                opened: false,
                artifacts: arts
            )
        }

        // If nothing needs producing, skip the open entirely and record skips.
        guard pendingExists else {
            let arts = project.expectedArtifacts.map { artifact in
                skippedArtifact(artifact, options: options, outputRoot: plan.outputRoot)
            }
            return RunProject(
                index: project.index,
                projectPath: project.projectPath,
                displayName: project.displayName,
                observedProjectPath: nil,
                identityVerified: false,
                opened: false,
                artifacts: arts
            )
        }

        // (3a) Open the project (existing open path through the router).
        let openResult = await router.route(
            operation: "project.open",
            params: ["path": project.projectPath]
        )
        guard openResult.isSuccess else {
            let arts = project.expectedArtifacts.map { artifact -> RunArtifact in
                artifactNeedsProduction(artifact, plan: plan)
                    ? failedArtifact(artifact, error: "open_failed: \(openResult.message)")
                    : skippedArtifact(artifact, options: options, outputRoot: plan.outputRoot)
            }
            return RunProject(
                index: project.index,
                projectPath: project.projectPath,
                displayName: project.displayName,
                observedProjectPath: nil,
                identityVerified: false,
                opened: false,
                artifacts: arts
            )
        }

        // (3b) Identity readback — the OBSERVED front document MUST match the
        // planned project path or we fail closed for every pending artifact
        // (never bounce the wrong project).
        let observedPath = await options.identityReadback()
        let identityVerified = observedPath.map {
            AppleScriptChannel.projectPathsMatch(project.projectPath, $0)
        } ?? false
        guard identityVerified else {
            let arts = project.expectedArtifacts.map { artifact -> RunArtifact in
                artifactNeedsProduction(artifact, plan: plan)
                    ? failedArtifact(
                        artifact,
                        error: observedPath == nil
                            ? "project_identity_mismatch: no front document path could be read"
                            : "project_identity_mismatch: observed=\(observedPath ?? "")"
                    )
                    : skippedArtifact(artifact, options: options, outputRoot: plan.outputRoot)
            }
            return RunProject(
                index: project.index,
                projectPath: project.projectPath,
                displayName: project.displayName,
                observedProjectPath: observedPath,
                identityVerified: false,
                opened: true,
                artifacts: arts
            )
        }

        // (3c) Per-artifact production.
        var arts: [RunArtifact] = []
        for artifact in project.expectedArtifacts {
            if !artifactNeedsProduction(artifact, plan: plan) {
                arts.append(skippedArtifact(artifact, options: options, outputRoot: plan.outputRoot))
                continue
            }
            let produced = await produce(
                artifact: artifact,
                plan: plan,
                router: router,
                options: options
            )
            arts.append(produced)
        }

        return RunProject(
            index: project.index,
            projectPath: project.projectPath,
            displayName: project.displayName,
            observedProjectPath: observedPath,
            identityVerified: true,
            opened: true,
            artifacts: arts
        )
    }

    // MARK: - Per-artifact production

    private static func produce(
        artifact: ProjectExportPlanArtifact,
        plan: ProjectExportPlan,
        router: ChannelRouter,
        options: Options
    ) async -> RunArtifact {
        // (5) Collision policy — under fail_if_exists an artifact the plan
        // flagged would_overwrite is NEVER overwritten. Fail closed.
        if artifact.verification.wouldOverwrite {
            return failedArtifact(
                artifact,
                error: "overwrite_blocked: collision_policy=\(plan.collisionPolicy) and artifact already exists"
            )
        }
        // Any other plan-level issue for this artifact (outside-root, zero-byte,
        // unreadable, intra-plan collision) is terminal — do not bounce.
        if !artifact.verification.issues.isEmpty {
            return failedArtifact(
                artifact,
                error: "artifact_blocked: \(artifact.verification.issues.joined(separator: ","))"
            )
        }

        // (3d) Trigger the bounce. The live seam (bounceToPath) drives a real
        // path-directed bounce via the cliclick helper and returns the produced
        // file; the legacy seam (nil, used by unit tests) fires the router bounce
        // and polls the planner-resolved path.
        let producedPath: String
        if let bounce = options.bounceToPath {
            let dir = (artifact.path as NSString).deletingLastPathComponent
            let base = ((artifact.path as NSString).lastPathComponent as NSString).deletingPathExtension
            guard let produced = await bounce(base, dir) else {
                return RunArtifact(
                    kind: artifact.kind,
                    path: artifact.path,
                    state: "C",
                    verified: false,
                    bounceFired: false,
                    error: "bounce_helper_failed: no verified artifact produced at \(dir)",
                    reason: nil,
                    evidence: nil
                )
            }
            producedPath = produced
        } else {
            let bounceResult = await router.route(operation: "project.bounce")
            guard bounceResult.isSuccess else {
                return RunArtifact(
                    kind: artifact.kind,
                    path: artifact.path,
                    state: "C",
                    verified: false,
                    bounceFired: false,
                    error: "bounce_failed: \(bounceResult.message)",
                    reason: nil,
                    evidence: nil
                )
            }
            // (3e) Bounded poll for the artifact file to appear on disk.
            let appeared = await waitForArtifact(path: artifact.path, options: options)
            guard appeared else {
                // State B — the bounce fired but the artifact never materialized in
                // the poll window. We canNOT claim success; we also did not hard-fail
                // the mutation, so this is honestly uncertain.
                return RunArtifact(
                    kind: artifact.kind,
                    path: artifact.path,
                    state: "B",
                    verified: false,
                    bounceFired: true,
                    error: nil,
                    reason: "artifact_not_observed_within_poll_window",
                    evidence: nil
                )
            }
            producedPath = artifact.path
        }

        // (3f) Verify with AudioAnalyzer (exists + non-zero + non-silent + sane
        // duration). State A ONLY when verification passes.
        let analysis = options.analyze(producedPath, analysisPolicy(plan: plan, options: options))
        let evidence = ArtifactEvidence(from: analysis, source: "audio_analyzer")
        if analysis.verification.status == .pass {
            return RunArtifact(
                kind: artifact.kind,
                path: producedPath,
                state: "A",
                verified: true,
                bounceFired: true,
                error: nil,
                reason: nil,
                evidence: evidence
            )
        }
        // Bounce fired, file present, but analysis did not pass (silent / short /
        // unreadable). State B — success uncertain, NOT verified.
        return RunArtifact(
            kind: artifact.kind,
            path: producedPath,
            state: "B",
            verified: false,
            bounceFired: true,
            error: nil,
            reason: "artifact_unverified: \(analysis.verification.reasons.joined(separator: ","))",
            evidence: evidence
        )
    }

    // MARK: - Helpers

    /// An artifact needs producing unless it is already present on disk AND
    /// passes verification (resume idempotency). Under any collision policy an
    /// existing+verified artifact is left untouched.
    private static func artifactNeedsProduction(
        _ artifact: ProjectExportPlanArtifact,
        plan: ProjectExportPlan
    ) -> Bool {
        // A plan-level issue other than would_overwrite (outside-root, zero-byte,
        // collision) still needs handling — surface it via produce()'s
        // fail-closed path, so treat it as "needs production" here.
        guard artifact.verification.exists else { return true }
        if artifact.verification.wouldOverwrite { return true }
        // Existing file under skip_existing (or otherwise non-overwriting) — only
        // skip when we can independently verify it. The verification itself is
        // re-checked in skippedArtifact(); here we use the plan's existence +
        // absence-of-issues as the cheap gate, and skippedArtifact downgrades to
        // State B if the on-disk verification fails.
        return false
    }

    /// Build the analyzer policy from the plan — pins output-root containment and
    /// the non-silence / minimum-duration gates that define a "sane" artifact.
    private static func analysisPolicy(plan: ProjectExportPlan, options: Options) -> AudioAnalyzer.AnalysisPolicy {
        var policy = AudioAnalyzer.AnalysisPolicy.default
        policy.outputRoot = plan.outputRoot
        policy.minimumDurationSeconds = options.minimumDurationSeconds
        policy.minimumFileSizeBytes = 1
        return policy
    }

    private static func waitForArtifact(path: String, options: Options) async -> Bool {
        var attempt = 0
        while attempt < max(1, options.pollAttempts) {
            var isDir: ObjCBool = false
            if options.fileManager.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue {
                return true
            }
            attempt += 1
            if attempt < options.pollAttempts {
                await options.sleep(options.pollIntervalNanos)
            }
        }
        // Final check after the last sleep.
        var isDir: ObjCBool = false
        return options.fileManager.fileExists(atPath: path, isDirectory: &isDir) && !isDir.boolValue
    }

    /// Record an artifact the plan reported as already present. We do NOT trust
    /// the plan's existence flag alone — re-verify on disk so a corrupt/zero/
    /// silent leftover is downgraded to State B instead of being skipped as a
    /// false State A.
    private static func skippedArtifact(
        _ artifact: ProjectExportPlanArtifact,
        options: Options,
        outputRoot: String
    ) -> RunArtifact {
        guard artifact.verification.exists, artifact.verification.issues.isEmpty else {
            // Should not reach here for a true skip, but stay honest if it does.
            return RunArtifact(
                kind: artifact.kind,
                path: artifact.path,
                state: "C",
                verified: false,
                bounceFired: false,
                error: "skip_precondition_failed",
                reason: nil,
                evidence: nil
            )
        }
        var policy = AudioAnalyzer.AnalysisPolicy.default
        policy.outputRoot = outputRoot
        policy.minimumDurationSeconds = options.minimumDurationSeconds
        policy.minimumFileSizeBytes = 1
        let analysis = options.analyze(artifact.path, policy)
        let evidence = ArtifactEvidence(from: analysis, source: "skip_reverify")
        guard analysis.verification.status == .pass else {
            return RunArtifact(
                kind: artifact.kind,
                path: artifact.path,
                state: "B",
                verified: false,
                bounceFired: false,
                error: nil,
                reason: "existing_artifact_unverified: \(analysis.verification.reasons.joined(separator: ","))",
                evidence: evidence
            )
        }
        return RunArtifact(
            kind: artifact.kind,
            path: artifact.path,
            state: "A",
            verified: true,
            bounceFired: false,
            error: nil,
            reason: "skipped_already_verified",
            evidence: evidence
        )
    }

    private static func failedArtifact(_ artifact: ProjectExportPlanArtifact, error: String) -> RunArtifact {
        RunArtifact(
            kind: artifact.kind,
            path: artifact.path,
            state: "C",
            verified: false,
            bounceFired: false,
            error: error,
            reason: nil,
            evidence: nil
        )
    }

    // MARK: - Aggregation

    private static func aggregate(
        plan: ProjectExportPlan,
        resume: Bool,
        projects: [RunProject]
    ) -> RunResult {
        let allArtifacts = projects.flatMap(\.artifacts)
        let verified = allArtifacts.filter { $0.state == "A" && $0.bounceFired }.count
        let skipped = allArtifacts.filter { $0.state == "A" && !$0.bounceFired }.count
        let uncertain = allArtifacts.filter { $0.state == "B" }.count
        let failed = allArtifacts.filter { $0.state == "C" }.count

        // Overall status: "completed" only when nothing failed and nothing is
        // uncertain; "partial" when some succeeded but others are uncertain/
        // failed; "failed" when nothing reached State A.
        let succeededCount = verified + skipped
        let status: String
        if failed == 0 && uncertain == 0 {
            status = "completed"
        } else if succeededCount > 0 {
            status = "partial"
        } else {
            status = "failed"
        }

        let nextSafeAction = status == "completed"
            ? "verify_artifacts_with_logic_audio"
            : "review_then_export_resume"

        return RunResult(
            schema: schema,
            runID: plan.runID,
            mode: resume ? "resume" : "run",
            confirmed: true,
            status: status,
            outputRoot: plan.outputRoot,
            collisionPolicy: plan.collisionPolicy,
            projectCount: projects.count,
            artifactsTotal: allArtifacts.count,
            artifactsVerified: verified,
            artifactsSkipped: skipped,
            artifactsUncertain: uncertain,
            artifactsFailed: failed,
            projects: projects,
            nextSafeAction: nextSafeAction
        )
    }

    private static func confirmationRequiredRun(plan: ProjectExportPlan, resume: Bool) -> RunResult {
        let arts = plan.projects.map { project in
            RunProject(
                index: project.index,
                projectPath: project.projectPath,
                displayName: project.displayName,
                observedProjectPath: nil,
                identityVerified: false,
                opened: false,
                artifacts: project.expectedArtifacts.map { artifact in
                    RunArtifact(
                        kind: artifact.kind,
                        path: artifact.path,
                        state: "C",
                        verified: false,
                        bounceFired: false,
                        error: "confirmation_required",
                        reason: nil,
                        evidence: nil
                    )
                }
            )
        }
        let total = arts.flatMap(\.artifacts).count
        return RunResult(
            schema: schema,
            runID: plan.runID,
            mode: resume ? "resume" : "run",
            confirmed: false,
            status: "confirmation_required",
            outputRoot: plan.outputRoot,
            collisionPolicy: plan.collisionPolicy,
            projectCount: plan.projects.count,
            artifactsTotal: total,
            artifactsVerified: 0,
            artifactsSkipped: 0,
            artifactsUncertain: 0,
            artifactsFailed: total,
            projects: arts,
            nextSafeAction: "retry_with_confirmed_true"
        )
    }

    private static func failedRun(
        runID: String,
        mode: String,
        confirmed: Bool,
        outputRoot: String,
        collisionPolicy: String,
        reason: String
    ) -> RunResult {
        RunResult(
            schema: schema,
            runID: runID,
            mode: mode,
            confirmed: confirmed,
            status: "failed",
            outputRoot: outputRoot,
            collisionPolicy: collisionPolicy,
            projectCount: 0,
            artifactsTotal: 0,
            artifactsVerified: 0,
            artifactsSkipped: 0,
            artifactsUncertain: 0,
            artifactsFailed: 0,
            projects: [],
            nextSafeAction: "fix_inputs_then_retry: \(reason)"
        )
    }
}

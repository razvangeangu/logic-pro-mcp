import Foundation

extension ProjectExportExecutor {
    static func aggregate(
        plan: ProjectExportPlan,
        resume: Bool,
        projects: [RunProject]
    ) -> RunResult {
        let allArtifacts = projects.flatMap(\.artifacts)
        let verified = allArtifacts.filter { $0.state == "A" && $0.bounceFired }.count
        let skipped = allArtifacts.filter { $0.state == "A" && !$0.bounceFired }.count
        let uncertain = allArtifacts.filter { $0.state == "B" }.count
        let failed = allArtifacts.filter { $0.state == "C" }.count
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

    static func confirmationRequiredRun(plan: ProjectExportPlan, resume: Bool) -> RunResult {
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

    static func failedRun(
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

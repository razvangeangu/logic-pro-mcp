import Foundation

extension ProjectExportExecutor {
    static func overwriteBlockedArtifact(
        _ artifact: ProjectExportPlanArtifact,
        plan: ProjectExportPlan,
        options: Options
    ) -> RunArtifact? {
        guard plan.collisionPolicy == "fail_if_exists" else { return nil }
        if let blockingPath = ProjectExportArtifactPathPolicy.preferredExistingVariant(
            for: artifact.path,
            fileManager: options.fileManager
        ) {
            return failedArtifact(
                artifact,
                error: "overwrite_blocked: collision_policy=\(plan.collisionPolicy) and artifact already exists at \(blockingPath)"
            )
        }
        if artifact.verification.wouldOverwrite {
            return failedArtifact(
                artifact,
                error: "overwrite_blocked: collision_policy=\(plan.collisionPolicy) and artifact already exists"
            )
        }
        return nil
    }

    static func preflightArtifactOutcome(
        _ artifact: ProjectExportPlanArtifact,
        plan: ProjectExportPlan,
        options: Options
    ) -> RunArtifact? {
        if let overwriteBlocked = overwriteBlockedArtifact(artifact, plan: plan, options: options) {
            return overwriteBlocked
        }
        if artifact.verification.exists {
            guard artifact.verification.issues.isEmpty else {
                return failedArtifact(
                    artifact,
                    error: "artifact_blocked: \(artifact.verification.issues.joined(separator: ","))"
                )
            }
            return skippedArtifact(artifact, options: options, outputRoot: plan.outputRoot)
        }
        guard artifact.verification.issues.isEmpty else {
            return failedArtifact(
                artifact,
                error: "artifact_blocked: \(artifact.verification.issues.joined(separator: ","))"
            )
        }
        return nil
    }

    static func produce(
        artifact: ProjectExportPlanArtifact,
        plan: ProjectExportPlan,
        router: ChannelRouter,
        options: Options
    ) async -> RunArtifact {
        if let overwriteBlocked = overwriteBlockedArtifact(artifact, plan: plan, options: options) {
            return overwriteBlocked
        }
        if !artifact.verification.issues.isEmpty {
            return failedArtifact(
                artifact,
                error: "artifact_blocked: \(artifact.verification.issues.joined(separator: ","))"
            )
        }

        let producedPath: String
        if let bounce = options.bounceToPath {
            let bounceResult = await bounce(artifact.path)
            guard let produced = bounceResult.artifactPath else {
                return RunArtifact(
                    kind: artifact.kind,
                    path: artifact.path,
                    state: "C",
                    verified: false,
                    bounceFired: bounceResult.bounceFired,
                    error: "bounce_helper_failed: \(bounceResult.error ?? "no verified artifact produced for \(artifact.path)")",
                    reason: nil,
                    evidence: nil
                )
            }
            guard ProjectExportArtifactPathPolicy.helperProducedPathMatchesPlannedStem(
                producedPath: produced,
                plannedPath: artifact.path
            ) else {
                return failedArtifact(
                    artifact,
                    error: "bounce_helper_unexpected_artifact_path: expected stem \(ProjectExportArtifactPathPolicy.standardizedStemPath(artifact.path)) but helper returned \(produced)",
                    bounceFired: true
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
            let appeared = await waitForArtifact(path: artifact.path, options: options)
            guard appeared else {
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

        let analysis = options.analyze(producedPath, analysisPolicy(plan: plan, options: options))
        if analysis.verification.reasons.contains("unsafe_path") {
            return failedArtifact(
                artifact,
                error: "artifact_path_unsafe: \(analysis.verification.detail ?? analysis.verification.reasons.joined(separator: ","))",
                bounceFired: true
            )
        }
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

    static func analysisPolicy(plan: ProjectExportPlan, options: Options) -> AudioAnalyzer.AnalysisPolicy {
        var policy = AudioAnalyzer.AnalysisPolicy.default
        policy.outputRoot = plan.outputRoot
        policy.minimumDurationSeconds = options.minimumDurationSeconds
        policy.minimumFileSizeBytes = 1
        return policy
    }

    static func waitForArtifact(path: String, options: Options) async -> Bool {
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
        var isDir: ObjCBool = false
        return options.fileManager.fileExists(atPath: path, isDirectory: &isDir) && !isDir.boolValue
    }

    static func skippedArtifact(
        _ artifact: ProjectExportPlanArtifact,
        options: Options,
        outputRoot: String
    ) -> RunArtifact {
        guard artifact.verification.exists,
              artifact.verification.issues.isEmpty,
              let existingPath = ProjectExportArtifactPathPolicy.preferredExistingVariant(
                  for: artifact.path,
                  fileManager: options.fileManager
              ) else {
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
        let analysis = options.analyze(existingPath, policy)
        if analysis.verification.reasons.contains("unsafe_path") {
            return RunArtifact(
                kind: artifact.kind,
                path: existingPath,
                state: "C",
                verified: false,
                bounceFired: false,
                error: "existing_artifact_path_unsafe: \(analysis.verification.detail ?? analysis.verification.reasons.joined(separator: ","))",
                reason: nil,
                evidence: nil
            )
        }
        let evidence = ArtifactEvidence(from: analysis, source: "skip_reverify")
        guard analysis.verification.status == .pass else {
            return RunArtifact(
                kind: artifact.kind,
                path: existingPath,
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
            path: existingPath,
            state: "A",
            verified: true,
            bounceFired: false,
            error: nil,
            reason: "skipped_already_verified",
            evidence: evidence
        )
    }

    static func failedArtifact(
        _ artifact: ProjectExportPlanArtifact,
        error: String,
        bounceFired: Bool = false
    ) -> RunArtifact {
        RunArtifact(
            kind: artifact.kind,
            path: artifact.path,
            state: "C",
            verified: false,
            bounceFired: bounceFired,
            error: error,
            reason: nil,
            evidence: nil
        )
    }
}

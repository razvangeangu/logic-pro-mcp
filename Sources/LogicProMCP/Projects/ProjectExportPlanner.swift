import Foundation
import MCP

struct ProjectExportPlan: Codable, Sendable, Equatable {
    let schema: String
    let runID: String
    let generatedAt: String
    let status: String
    let executionMode: String
    let outputRoot: String
    let collisionPolicy: String
    let namingPolicy: String
    let projectCount: Int
    let projects: [ProjectExportPlanProject]
    let requiredConfirmations: [ProjectExportConfirmation]
    let unsupportedOrBlockedSteps: [ProjectExportBlockedStep]
    let baselineVerification: [String]
    let enhancementPath: [String]
    let nextSafeAction: String

    enum CodingKeys: String, CodingKey {
        case schema
        case runID = "run_id"
        case generatedAt = "generated_at"
        case status
        case executionMode = "execution_mode"
        case outputRoot = "output_root"
        case collisionPolicy = "collision_policy"
        case namingPolicy = "naming_policy"
        case projectCount = "project_count"
        case projects
        case requiredConfirmations = "required_confirmations"
        case unsupportedOrBlockedSteps = "unsupported_or_blocked_steps"
        case baselineVerification = "baseline_verification"
        case enhancementPath = "enhancement_path"
        case nextSafeAction = "next_safe_action"
    }
}

struct ProjectExportPlanProject: Codable, Sendable, Equatable {
    let index: Int
    let projectPath: String
    let displayName: String
    let validationStatus: String
    let validationIssues: [String]
    let expectedArtifacts: [ProjectExportPlanArtifact]
    let workflowSteps: [ProjectExportWorkflowStep]
    let manifestStatus: String

    enum CodingKeys: String, CodingKey {
        case index
        case projectPath = "project_path"
        case displayName = "display_name"
        case validationStatus = "validation_status"
        case validationIssues = "validation_issues"
        case expectedArtifacts = "expected_artifacts"
        case workflowSteps = "workflow_steps"
        case manifestStatus = "manifest_status"
    }
}

struct ProjectExportPlanArtifact: Codable, Sendable, Equatable {
    let kind: String
    let path: String
    let status: String
    let verification: ProjectExportArtifactVerification
    let analysis: [String: String]

    enum CodingKeys: String, CodingKey {
        case kind
        case path
        case status
        case verification
        case analysis
    }
}

struct ProjectExportArtifactVerification: Codable, Sendable, Equatable {
    let exists: Bool
    let fileSizeBytes: Int64?
    let mtime: String?
    let pathUnderOutputRoot: Bool
    let wouldOverwrite: Bool
    let issues: [String]

    enum CodingKeys: String, CodingKey {
        case exists
        case fileSizeBytes = "file_size_bytes"
        case mtime
        case pathUnderOutputRoot = "path_under_output_root"
        case wouldOverwrite = "would_overwrite"
        case issues
    }
}

struct ProjectExportWorkflowStep: Codable, Sendable, Equatable {
    let id: String
    let title: String
    let tool: String?
    let command: String?
    let mutates: Bool
    let executed: Bool
    let requiresConfirmationLevel: String?
    let stopConditions: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case tool
        case command
        case mutates
        case executed
        case requiresConfirmationLevel = "requires_confirmation_level"
        case stopConditions = "stop_conditions"
    }
}

struct ProjectExportConfirmation: Codable, Sendable, Equatable {
    let level: String
    let requiredFor: [String]
    let message: String

    enum CodingKeys: String, CodingKey {
        case level
        case requiredFor = "required_for"
        case message
    }
}

struct ProjectExportBlockedStep: Codable, Sendable, Equatable {
    let operation: String
    let reason: String
    let safeAlternative: String

    enum CodingKeys: String, CodingKey {
        case operation
        case reason
        case safeAlternative = "safe_alternative"
    }
}

enum ProjectExportPlanner {
    static let schema = "logic_pro_mcp_export_manifest.v1"
    static let supportedArtifactKinds: Set<String> = ["bounce", "stem", "preview", "variant"]

    static func plan(params: [String: Value], fileManager: FileManager = .default) throws -> ProjectExportPlan {
        let projects = try projectPaths(from: params)
        let outputRoot = try outputRoot(from: params)
        let artifacts = try artifactKinds(from: params)
        let collisionPolicy = stringParam(params, "collision_policy", default: "fail_if_exists")
        guard ["fail_if_exists", "skip_existing"].contains(collisionPolicy) else {
            throw ExportPlanError.invalid("collision_policy must be fail_if_exists or skip_existing")
        }
        let namingPolicy = stringParam(params, "naming_policy", default: "project-name-kind")

        let rootURL = URL(fileURLWithPath: outputRoot).standardizedFileURL
        let projectPlans = projects.enumerated().map { index, path in
            projectPlan(
                index: index,
                path: path,
                outputRoot: rootURL,
                artifactKinds: artifacts,
                collisionPolicy: collisionPolicy,
                fileManager: fileManager
            )
        }

        // PR99-C1 / PR99-edge-2 / PR99-edge-3: aggregate every resolved artifact
        // path across ALL projects and flag any path produced by 2+ artifacts so
        // batch exports cannot silently overwrite each other (defeating
        // no_silent_overwrite). Comparison is case-insensitive because the default
        // macOS volumes (APFS/HFS+) are case-insensitive, so 'Song' and 'song'
        // collide on disk too. Each colliding artifact gets a forced issue, which
        // flips the plan to "degraded" via the existing non-empty-issues predicate.
        let resolvedProjectPlans = flagIntraPlanCollisions(projectPlans)

        let blocked = blockedSteps()
        let status = resolvedProjectPlans.contains { project in
            project.validationStatus != "valid" ||
                project.expectedArtifacts.contains { !$0.verification.issues.isEmpty }
        }
            ? "degraded"
            : "planned"

        return ProjectExportPlan(
            schema: schema,
            runID: deterministicRunID(projects: projects, outputRoot: outputRoot, artifacts: artifacts),
            // C3: real run-window anchor so the advertised mtime_within_run_window
            // gate is evaluable — an executor bounds post-export mtime to >= this.
            generatedAt: ISO8601DateFormatter.cacheFormatter.string(from: Date()),
            status: status,
            executionMode: "dry_run_only",
            outputRoot: outputRoot,
            collisionPolicy: collisionPolicy,
            namingPolicy: namingPolicy,
            projectCount: resolvedProjectPlans.count,
            projects: resolvedProjectPlans,
            requiredConfirmations: [
                ProjectExportConfirmation(
                    level: "L2",
                    requiredFor: ["open", "bounce"],
                    message: "Batch export execution must confirm every project open and export/bounce boundary before mutation."
                ),
                // C1: close is canonically gated at L3 by DestructivePolicy; the
                // manifest must declare the SAME boundary a future executor enforces.
                ProjectExportConfirmation(
                    level: confirmationLabel(for: "close"),
                    requiredFor: ["close"],
                    message: "Closing a project may discard unsaved changes; confirm the close/save-prompt boundary before mutation."
                ),
            ],
            unsupportedOrBlockedSteps: blocked,
            baselineVerification: [
                "artifact_exists",
                "file_size_non_zero",
                "mtime_within_run_window",
                "path_under_output_root",
                "no_silent_overwrite",
            ],
            enhancementPath: [
                "After a real bounce/export, verify each produced artifact with logic_audio.analyze_file (logic_pro_mcp_audio_analysis.v1) for duration, non-silence, peak/clipping, sample-rate, channels, and honest loudness estimates.",
            ],
            nextSafeAction: "review_export_plan"
        )
    }

    private static func projectPlan(
        index: Int,
        path: String,
        outputRoot: URL,
        artifactKinds: [String],
        collisionPolicy: String,
        fileManager: FileManager
    ) -> ProjectExportPlanProject {
        var issues: [String] = []
        if !AppleScriptSafety.isValidProjectPath(path, requireExisting: false) {
            issues.append("project_path_must_be_absolute_logicx")
        }
        if !fileManager.fileExists(atPath: path) {
            issues.append("project_path_not_found")
        }

        let projectURL = URL(fileURLWithPath: path).standardizedFileURL
        let displayName = projectURL.deletingPathExtension().lastPathComponent
        let artifactPlans = artifactKinds.map { kind in
            artifact(
                kind: kind,
                displayName: displayName,
                outputRoot: outputRoot,
                collisionPolicy: collisionPolicy,
                fileManager: fileManager
            )
        }

        return ProjectExportPlanProject(
            index: index,
            projectPath: path,
            displayName: displayName,
            validationStatus: issues.isEmpty ? "valid" : "invalid",
            validationIssues: issues,
            expectedArtifacts: artifactPlans,
            workflowSteps: workflowSteps(for: index),
            manifestStatus: "pending"
        )
    }

    private static func artifact(
        kind: String,
        displayName: String,
        outputRoot: URL,
        collisionPolicy: String,
        fileManager: FileManager
    ) -> ProjectExportPlanArtifact {
        // PR99-C2: validate containment against the PRE-sanitization candidate so
        // the check is non-vacuous. A raw displayName containing ".." or a path
        // separator can resolve outside outputRoot once standardized; the sanitized
        // url below can never express that, so it alone could only ever be true.
        let rawComponent = "\(displayName)-\(kind).wav"
        let candidate = outputRoot.appendingPathComponent(rawComponent).standardizedFileURL
        let underRoot = candidate.path == outputRoot.path || candidate.path.hasPrefix(outputRoot.path + "/")

        let safeProject = sanitizeFileComponent(displayName)
        let url = outputRoot.appendingPathComponent("\(safeProject)-\(kind).wav").standardizedFileURL
        let exists = fileManager.fileExists(atPath: url.path)
        let attrs = try? fileManager.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value
        let mtime = (attrs?[.modificationDate] as? Date).map {
            ISO8601DateFormatter.cacheFormatter.string(from: $0)
        }
        var issues: [String] = []
        if !underRoot {
            issues.append("artifact_path_outside_output_root")
        }
        if exists && collisionPolicy == "fail_if_exists" {
            issues.append("artifact_would_overwrite")
        }
        // PR99-C3: only assert a definite zero-byte artifact when the size is a
        // concrete value. A vanished/unreadable file (TOCTOU, permissions, or a
        // directory/special file at the path) yields a nil size — that is
        // "unknown", not "zero", so emit a distinct token instead of lying.
        if exists, let size, size == 0 {
            issues.append("artifact_zero_bytes")
        } else if exists, size == nil {
            issues.append("artifact_size_unreadable")
        }

        return ProjectExportPlanArtifact(
            kind: kind,
            path: url.path,
            status: exists ? "existing" : "pending",
            verification: ProjectExportArtifactVerification(
                exists: exists,
                fileSizeBytes: size,
                mtime: mtime,
                pathUnderOutputRoot: underRoot,
                wouldOverwrite: exists && collisionPolicy == "fail_if_exists",
                issues: issues
            ),
            analysis: ["issue_29": "not_run_in_dry_run"]
        )
    }

    private static func workflowSteps(for index: Int) -> [ProjectExportWorkflowStep] {
        [
            ProjectExportWorkflowStep(
                id: "project_\(index)_open",
                title: "Open project after confirming expected path",
                tool: "logic_project",
                command: "open",
                mutates: true,
                executed: false,
                requiresConfirmationLevel: confirmationLabel(for: "open"),
                stopConditions: ["wrong_project_observed", "open_failed", "ambiguous_save_state"]
            ),
            ProjectExportWorkflowStep(
                id: "project_\(index)_export",
                title: "Trigger approved bounce/export operation",
                tool: "logic_project",
                command: "bounce",
                mutates: true,
                executed: false,
                requiresConfirmationLevel: confirmationLabel(for: "bounce"),
                stopConditions: ["missing_output", "stale_output", "overwrite_risk"]
            ),
            ProjectExportWorkflowStep(
                id: "project_\(index)_close",
                title: "Close or leave project according to explicit policy",
                tool: "logic_project",
                command: "close",
                mutates: true,
                executed: false,
                // C1: drive from the canonical policy (close == L3) instead of
                // hardcoding L2, so the contract matches the enforced boundary.
                requiresConfirmationLevel: confirmationLabel(for: "close"),
                stopConditions: ["ambiguous_close_state", "save_prompt_unresolved"]
            ),
        ]
    }

    /// Map a lifecycle command to its manifest confirmation label using the
    /// canonical DestructivePolicy as the single source of truth (close/quit ==
    /// L3, open/bounce/save_as == L2). Keeps the dry-run contract in lockstep
    /// with the boundary the live dispatcher actually enforces.
    private static func confirmationLabel(for command: String) -> String {
        DestructivePolicy.level(for: command) == .l3 ? "L3" : "L2"
    }

    /// PR99-C1 / PR99-edge-2 / PR99-edge-3: detect artifact paths that two or
    /// more planned artifacts resolve to (across all projects in the batch) and
    /// append a collision issue to each, forcing the plan to "degraded". Path
    /// comparison is case-insensitive to match the case-insensitive default
    /// macOS volume, so distinct-cased slugs that map to the same on-disk file
    /// are caught. Artifacts are immutable value types, so this is a rebuild pass.
    private static func flagIntraPlanCollisions(
        _ plans: [ProjectExportPlanProject]
    ) -> [ProjectExportPlanProject] {
        var pathCounts: [String: Int] = [:]
        for project in plans {
            for art in project.expectedArtifacts {
                pathCounts[art.path.lowercased(), default: 0] += 1
            }
        }
        let collidingPaths = Set(pathCounts.filter { $0.value > 1 }.keys)
        guard !collidingPaths.isEmpty else { return plans }

        return plans.map { project in
            let arts = project.expectedArtifacts.map { art -> ProjectExportPlanArtifact in
                guard collidingPaths.contains(art.path.lowercased()) else { return art }
                let v = art.verification
                return ProjectExportPlanArtifact(
                    kind: art.kind,
                    path: art.path,
                    status: art.status,
                    verification: ProjectExportArtifactVerification(
                        exists: v.exists,
                        fileSizeBytes: v.fileSizeBytes,
                        mtime: v.mtime,
                        pathUnderOutputRoot: v.pathUnderOutputRoot,
                        wouldOverwrite: v.wouldOverwrite,
                        issues: v.issues + ["artifact_path_collides_in_plan"]
                    ),
                    analysis: art.analysis
                )
            }
            return ProjectExportPlanProject(
                index: project.index,
                projectPath: project.projectPath,
                displayName: project.displayName,
                validationStatus: project.validationStatus,
                validationIssues: project.validationIssues,
                expectedArtifacts: arts,
                workflowSteps: project.workflowSteps,
                manifestStatus: project.manifestStatus
            )
        }
    }

    private static func blockedSteps() -> [ProjectExportBlockedStep] {
        [
            ProjectExportBlockedStep(
                operation: "export_run",
                reason: "Guarded execution requires scoped live Logic export evidence before production-ready exposure.",
                safeAlternative: "Use export_plan to review paths, artifacts, confirmations, and manifest expectations."
            ),
            ProjectExportBlockedStep(
                operation: "export_resume",
                reason: "Resume must reconcile against durable manifests and post-export analysis before skipping work.",
                safeAlternative: "Use the dry-run plan as the manifest contract until execution evidence lands."
            ),
            ProjectExportBlockedStep(
                operation: "cloud_delivery",
                reason: "Cloud upload, email, and external sharing are explicitly out of scope.",
                safeAlternative: "Write artifacts only under the approved local output root."
            ),
        ]
    }

    private static func projectPaths(from params: [String: Value]) throws -> [String] {
        if let array = params["projects"]?.arrayValue {
            let paths = array.compactMap { $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard paths.count == array.count, !paths.isEmpty else {
                throw ExportPlanError.invalid("projects must be a non-empty array of absolute .logicx paths")
            }
            return paths
        }
        // PR99-edge-1: trim identically to the array branch so a stray leading
        // space cannot make `project` resolve relative to CWD while `projects:[...]`
        // resolves absolutely — the two input shapes must normalize the same way.
        let path = stringParam(params, "project", "path")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            throw ExportPlanError.invalid("export_plan requires projects or project/path")
        }
        return [path]
    }

    private static func outputRoot(from params: [String: Value]) throws -> String {
        let root = stringParam(params, "output_root", "outputRoot")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard root.hasPrefix("/") else {
            throw ExportPlanError.invalid("output_root must be an absolute local path")
        }
        // PR99-edge-4: `standardizedFileURL` collapses `..` segments, so a root
        // like "/Users/x/../../etc/out" resolves to "/etc/out". We do NOT silently
        // honor traversal — block roots that resolve under known system prefixes
        // (beyond the existing /dev guard) so a malformed/abusive output_root
        // cannot target system locations. The emitted output_root is always the
        // standardized (post-collapse) path, which is what callers/executors see.
        let standardized = URL(fileURLWithPath: root).standardizedFileURL.path
        let blockedPrefixes = ["/dev/", "/System/", "/private/var/db/", "/etc/", "/bin/", "/sbin/", "/usr/bin/", "/usr/sbin/"]
        guard !blockedPrefixes.contains(where: { standardized == String($0.dropLast()) || standardized.hasPrefix($0) }) else {
            throw ExportPlanError.invalid("output_root must not resolve to a system location: \(standardized)")
        }
        return standardized
    }

    private static func artifactKinds(from params: [String: Value]) throws -> [String] {
        let raw: [String]
        if let array = params["artifacts"]?.arrayValue {
            raw = array.compactMap { $0.stringValue?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            guard raw.count == array.count else {
                throw ExportPlanError.invalid("artifacts must be an array of strings")
            }
        } else {
            raw = [stringParam(params, "artifact", "kind", default: "bounce").lowercased()]
        }
        let cleaned = raw.filter { !$0.isEmpty }
        guard !cleaned.isEmpty else {
            throw ExportPlanError.invalid("at least one artifact kind is required")
        }
        let unsupported = cleaned.filter { !supportedArtifactKinds.contains($0) }
        guard unsupported.isEmpty else {
            throw ExportPlanError.invalid("unsupported artifact kind(s): \(unsupported.joined(separator: ","))")
        }
        return Array(Set(cleaned)).sorted()
    }

    private static func deterministicRunID(projects: [String], outputRoot: String, artifacts: [String]) -> String {
        // PR99-C4: 64-bit FNV-1a, zero-padded to 16 hex. The prior 32-bit digest
        // had a ~50% birthday-collision probability at only ~77k distinct inputs;
        // run_id is part of the v1 manifest contract a future resume consumer keys
        // off, so widen now while no reconciliation consumer has shipped.
        let seed = ([outputRoot] + projects + artifacts).joined(separator: "|")
        let hash = seed.utf8.reduce(UInt64(14695981039346656037)) { partial, byte in
            (partial ^ UInt64(byte)) &* 1099511628211
        }
        return "export-" + String(format: "%016llx", hash)
    }

    private static func sanitizeFileComponent(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = raw.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : Character("-")
        }
        let value = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return value.isEmpty ? "project" : value
    }
}

enum ExportPlanError: Error, CustomStringConvertible {
    case invalid(String)

    var description: String {
        switch self {
        case .invalid(let message):
            return message
        }
    }
}

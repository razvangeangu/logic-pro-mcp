import Foundation
import MCP

struct ProjectExportPlan: Codable, Sendable, Equatable {
    let schema: String
    let runID: String
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

        let blocked = blockedSteps()
        let status = projectPlans.contains { project in
            project.validationStatus != "valid" ||
                project.expectedArtifacts.contains { !$0.verification.issues.isEmpty }
        }
            ? "degraded"
            : "planned"

        return ProjectExportPlan(
            schema: schema,
            runID: deterministicRunID(projects: projects, outputRoot: outputRoot, artifacts: artifacts),
            status: status,
            executionMode: "dry_run_only",
            outputRoot: outputRoot,
            collisionPolicy: collisionPolicy,
            namingPolicy: namingPolicy,
            projectCount: projectPlans.count,
            projects: projectPlans,
            requiredConfirmations: [
                ProjectExportConfirmation(
                    level: "L2",
                    requiredFor: ["open", "bounce", "close"],
                    message: "Batch export execution must confirm every project open, export/bounce, and close boundary before mutation."
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
                "Integrate Issue #29 audio analysis for duration, non-silence, peak/clipping, sample-rate, channels, and honest loudness estimates.",
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
        let safeProject = sanitizeFileComponent(displayName)
        let url = outputRoot.appendingPathComponent("\(safeProject)-\(kind).wav").standardizedFileURL
        let exists = fileManager.fileExists(atPath: url.path)
        let attrs = try? fileManager.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? NSNumber)?.int64Value
        let mtime = (attrs?[.modificationDate] as? Date).map {
            ISO8601DateFormatter.cacheFormatter.string(from: $0)
        }
        let underRoot = url.path == outputRoot.path || url.path.hasPrefix(outputRoot.path + "/")
        var issues: [String] = []
        if !underRoot {
            issues.append("artifact_path_outside_output_root")
        }
        if exists && collisionPolicy == "fail_if_exists" {
            issues.append("artifact_would_overwrite")
        }
        if exists && (size ?? 0) == 0 {
            issues.append("artifact_zero_bytes")
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
                requiresConfirmationLevel: "L2",
                stopConditions: ["wrong_project_observed", "open_failed", "ambiguous_save_state"]
            ),
            ProjectExportWorkflowStep(
                id: "project_\(index)_export",
                title: "Trigger approved bounce/export operation",
                tool: "logic_project",
                command: "bounce",
                mutates: true,
                executed: false,
                requiresConfirmationLevel: "L2",
                stopConditions: ["missing_output", "stale_output", "overwrite_risk"]
            ),
            ProjectExportWorkflowStep(
                id: "project_\(index)_close",
                title: "Close or leave project according to explicit policy",
                tool: "logic_project",
                command: "close",
                mutates: true,
                executed: false,
                requiresConfirmationLevel: "L2",
                stopConditions: ["ambiguous_close_state", "save_prompt_unresolved"]
            ),
        ]
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
        let path = stringParam(params, "project", "path")
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
        let standardized = URL(fileURLWithPath: root).standardizedFileURL.path
        guard !standardized.hasPrefix("/dev/") else {
            throw ExportPlanError.invalid("output_root must not be under /dev")
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
        let seed = ([outputRoot] + projects + artifacts).joined(separator: "|")
        let hash = seed.utf8.reduce(UInt32(2166136261)) { partial, byte in
            (partial ^ UInt32(byte)) &* 16777619
        }
        return "export-\(String(hash, radix: 16))"
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

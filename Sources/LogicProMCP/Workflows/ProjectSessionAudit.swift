import Foundation

enum ProjectSessionAudit {
    static let auditSchema = "logic_pro_mcp_project_audit.v1"
    static let cleanupPlanSchema = "logic_pro_mcp_project_cleanup_plan.v1"

    private static let staleThresholdSeconds = 30.0

    enum Status: String, Codable, Sendable {
        case ok
        case degraded
        case failed
    }

    enum Severity: String, Codable, Sendable {
        case info
        case warn
        case blocker
    }

    enum RiskLevel: String, Codable, Sendable {
        case low
        case medium
        case high
    }

    struct AuditReport: Codable, Sendable {
        let schema: String
        let status: Status
        let generatedAt: String
        let readOnly: Bool
        let project: ProjectEvidence
        let evidence: Evidence
        let findings: [Finding]
        let cleanupPlan: [CleanupPlanStep]

        enum CodingKeys: String, CodingKey {
            case schema
            case status
            case generatedAt = "generated_at"
            case readOnly = "read_only"
            case project
            case evidence
            case findings
            case cleanupPlan = "cleanup_plan"
        }
    }

    struct CleanupPlanReport: Codable, Sendable {
        let schema: String
        let sourceAuditSchema: String
        let status: Status
        let generatedAt: String
        let readOnly: Bool
        let requiresPlanConfirmation: Bool
        let steps: [CleanupPlanStep]

        enum CodingKeys: String, CodingKey {
            case schema
            case sourceAuditSchema = "source_audit_schema"
            case status
            case generatedAt = "generated_at"
            case readOnly = "read_only"
            case requiresPlanConfirmation = "requires_plan_confirmation"
            case steps
        }
    }

    struct ProjectEvidence: Codable, Sendable {
        let name: String
        let filePath: String?
        let sampleRate: Int
        let tempo: Double
        let timeSignature: String
        let trackCount: Int
        let provenance: String

        enum CodingKeys: String, CodingKey {
            case name
            case filePath = "file_path"
            case sampleRate = "sample_rate"
            case tempo
            case timeSignature = "time_signature"
            case trackCount = "track_count"
            case provenance
        }
    }

    struct Evidence: Codable, Sendable {
        let hasDocument: Bool
        let axOccluded: Bool
        let project: EvidenceFreshness
        let transport: TransportEvidence
        let tracks: TrackEvidence
        let regions: CountEvidence
        let markers: CountEvidence
        let mixer: MixerEvidence
        let exportReadiness: ExportReadiness

        enum CodingKeys: String, CodingKey {
            case hasDocument = "has_document"
            case axOccluded = "ax_occluded"
            case project
            case transport
            case tracks
            case regions
            case markers
            case mixer
            case exportReadiness = "export_readiness"
        }
    }

    struct EvidenceFreshness: Codable, Sendable {
        let available: Bool
        let provenance: String
        let fetchedAt: String?
        let cacheAgeSec: Double?
        let stale: Bool

        enum CodingKeys: String, CodingKey {
            case available
            case provenance
            case fetchedAt = "fetched_at"
            case cacheAgeSec = "cache_age_sec"
            case stale
        }
    }

    struct TransportEvidence: Codable, Sendable {
        let state: TransportState
        let freshness: EvidenceFreshness
    }

    struct TrackEvidence: Codable, Sendable {
        let total: Int
        let freshness: EvidenceFreshness
        let selectedIndices: [Int]
        let mutedIndices: [Int]
        let soloedIndices: [Int]
        let armedIndices: [Int]
        let unnamedTrackIndices: [Int]
        let placeholderIndices: [Int]
        let duplicateNames: [DuplicateNameGroup]

        enum CodingKeys: String, CodingKey {
            case total
            case freshness
            case selectedIndices = "selected_indices"
            case mutedIndices = "muted_indices"
            case soloedIndices = "soloed_indices"
            case armedIndices = "armed_indices"
            case unnamedTrackIndices = "unnamed_track_indices"
            case placeholderIndices = "placeholder_indices"
            case duplicateNames = "duplicate_names"
        }
    }

    struct DuplicateNameGroup: Codable, Sendable {
        let name: String
        let indices: [Int]
    }

    struct CountEvidence: Codable, Sendable {
        let count: Int
        let freshness: EvidenceFreshness
    }

    struct MixerEvidence: Codable, Sendable {
        let stripCount: Int
        let dataSource: String
        let freshness: EvidenceFreshness
        let occupiedPluginSlots: [PluginSlotEvidence]
        let pluginReadErrors: [String]

        enum CodingKeys: String, CodingKey {
            case stripCount = "strip_count"
            case dataSource = "data_source"
            case freshness
            case occupiedPluginSlots = "occupied_plugin_slots"
            case pluginReadErrors = "plugin_read_errors"
        }
    }

    struct PluginSlotEvidence: Codable, Sendable {
        let trackIndex: Int
        let slotIndex: Int
        let name: String

        enum CodingKeys: String, CodingKey {
            case trackIndex = "track_index"
            case slotIndex = "slot_index"
            case name
        }
    }

    struct ExportReadiness: Codable, Sendable {
        let status: String
        let blockers: [String]
        let warnings: [String]
    }

    struct Finding: Codable, Sendable {
        let id: String
        let severity: Severity
        let category: String
        let summary: String
        let evidence: FindingEvidence
        let provenance: String
    }

    struct FindingEvidence: Codable, Sendable {
        let resource: String
        let target: String?
        let values: [String]

        enum CodingKeys: String, CodingKey {
            case resource
            case target
            case values
        }
    }

    struct CleanupPlanStep: Codable, Sendable {
        let id: String
        let targetIdentifier: String
        let proposedOperation: String
        let rationale: String
        let riskLevel: RiskLevel
        let requiredConfirmation: String
        let expectedReadback: String
        let rollbackOrRecovery: String
        let stopCondition: String
        let supportedByCurrentTools: Bool
        let mutatesProject: Bool
        let tool: String?
        let command: String?

        enum CodingKeys: String, CodingKey {
            case id
            case targetIdentifier = "target_identifier"
            case proposedOperation = "proposed_operation"
            case rationale
            case riskLevel = "risk_level"
            case requiredConfirmation = "required_confirmation"
            case expectedReadback = "expected_readback"
            case rollbackOrRecovery = "rollback_or_recovery"
            case stopCondition = "stop_condition"
            case supportedByCurrentTools = "supported_by_current_tools"
            case mutatesProject = "mutates_project"
            case tool
            case command
        }
    }

    struct Snapshot: Sendable {
        let now: Date
        let hasDocument: Bool
        let axOccluded: Bool
        let project: ProjectInfo
        let projectFetchedAt: Date
        let transport: TransportState
        let tracks: [TrackState]
        let tracksFetchedAt: Date
        let regions: [RegionState]
        let regionsFetchedAt: Date
        let markers: [MarkerState]
        let markersFetchedAt: Date
        let channelStrips: [ChannelStripState]
        let mixerFetchedAt: Date
    }

    static func buildAudit(cache: StateCache, now: Date = Date()) async -> AuditReport {
        let snapshot = Snapshot(
            now: now,
            hasDocument: await cache.getHasDocument(),
            axOccluded: await cache.getAXOccluded(),
            project: await cache.getProject(),
            projectFetchedAt: await cache.getProjectFetchedAt(),
            transport: await cache.getTransport(),
            tracks: await cache.getTracks(),
            tracksFetchedAt: await cache.getTracksFetchedAt(),
            regions: await cache.getRegions(),
            regionsFetchedAt: await cache.getRegionsFetchedAt(),
            markers: await cache.getMarkers(),
            markersFetchedAt: await cache.getMarkersFetchedAt(),
            channelStrips: await cache.getChannelStrips(),
            mixerFetchedAt: await cache.getMixerFetchedAt()
        )
        return buildAudit(snapshot: snapshot)
    }

    static func buildCleanupPlan(cache: StateCache, now: Date = Date()) async -> CleanupPlanReport {
        let audit = await buildAudit(cache: cache, now: now)
        return CleanupPlanReport(
            schema: cleanupPlanSchema,
            sourceAuditSchema: audit.schema,
            status: audit.status,
            generatedAt: audit.generatedAt,
            readOnly: true,
            requiresPlanConfirmation: true,
            steps: audit.cleanupPlan
        )
    }

    static func buildAudit(snapshot: Snapshot) -> AuditReport {
        let project = ProjectEvidence(
            name: snapshot.project.name,
            filePath: snapshot.project.filePath,
            sampleRate: snapshot.project.sampleRate,
            tempo: snapshot.project.tempo,
            timeSignature: snapshot.project.timeSignature,
            trackCount: snapshot.project.trackCount,
            provenance: snapshot.project.source ?? freshness(
                fetchedAt: snapshot.projectFetchedAt,
                fallbackProvenance: "cache",
                now: snapshot.now
            ).provenance
        )

        let duplicateNames = duplicateNameGroups(snapshot.tracks)
        let unnamed = snapshot.tracks
            .filter { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ($0.placeholder ?? false) }
            .map(\.id)
        let placeholders = snapshot.tracks.filter { $0.placeholder == true }.map(\.id)
        let muted = snapshot.tracks.filter(\.isMuted).map(\.id)
        let soloed = snapshot.tracks.filter(\.isSoloed).map(\.id)
        let armed = snapshot.tracks.filter(\.isArmed).map(\.id)
        let selected = snapshot.tracks.filter(\.isSelected).map(\.id)

        let tracksEvidence = TrackEvidence(
            total: snapshot.tracks.count,
            freshness: freshness(fetchedAt: snapshot.tracksFetchedAt, fallbackProvenance: "ax_live", now: snapshot.now),
            selectedIndices: selected,
            mutedIndices: muted,
            soloedIndices: soloed,
            armedIndices: armed,
            unnamedTrackIndices: unnamed,
            placeholderIndices: placeholders,
            duplicateNames: duplicateNames
        )

        let mixerDataSource = ResourceHandlers.mixerDataSource(fetchedAt: snapshot.mixerFetchedAt, now: snapshot.now)
        let mixerEvidence = MixerEvidence(
            stripCount: snapshot.channelStrips.count,
            dataSource: mixerDataSource,
            freshness: freshness(fetchedAt: snapshot.mixerFetchedAt, fallbackProvenance: mixerDataSource, now: snapshot.now),
            occupiedPluginSlots: occupiedPluginSlots(snapshot.channelStrips),
            pluginReadErrors: snapshot.channelStrips.compactMap(\.pluginsReadError)
        )

        var findings = deterministicFindings(
            snapshot: snapshot,
            project: project,
            tracks: tracksEvidence,
            mixer: mixerEvidence
        )
        findings.sort { $0.id < $1.id }

        let exportReadiness = exportReadiness(from: findings)
        let status = reportStatus(from: findings)
        let cleanupPlan = cleanupPlanSteps(
            snapshot: snapshot,
            findings: findings,
            duplicateNames: duplicateNames,
            unnamedTrackIndices: unnamed,
            emptyTrackIndices: emptyTrackIndices(snapshot)
        )

        return AuditReport(
            schema: auditSchema,
            status: status,
            generatedAt: ISO8601DateFormatter.cacheFormatter.string(from: snapshot.now),
            readOnly: true,
            project: project,
            evidence: Evidence(
                hasDocument: snapshot.hasDocument,
                axOccluded: snapshot.axOccluded,
                project: freshness(
                    fetchedAt: snapshot.projectFetchedAt,
                    fallbackProvenance: project.provenance,
                    now: snapshot.now
                ),
                transport: TransportEvidence(
                    state: snapshot.transport,
                    freshness: freshness(
                        fetchedAt: snapshot.transport.lastUpdated,
                        fallbackProvenance: "ax_live",
                        now: snapshot.now
                    )
                ),
                tracks: tracksEvidence,
                regions: CountEvidence(
                    count: snapshot.regions.count,
                    freshness: freshness(fetchedAt: snapshot.regionsFetchedAt, fallbackProvenance: "ax_live", now: snapshot.now)
                ),
                markers: CountEvidence(
                    count: snapshot.markers.count,
                    freshness: freshness(fetchedAt: snapshot.markersFetchedAt, fallbackProvenance: "ax_live", now: snapshot.now)
                ),
                mixer: mixerEvidence,
                exportReadiness: exportReadiness
            ),
            findings: findings,
            cleanupPlan: cleanupPlan
        )
    }

    private static func deterministicFindings(
        snapshot: Snapshot,
        project: ProjectEvidence,
        tracks: TrackEvidence,
        mixer: MixerEvidence
    ) -> [Finding] {
        var findings: [Finding] = []

        if !snapshot.hasDocument {
            findings.append(finding(
                "no_open_document",
                .blocker,
                "system",
                "No open Logic document is confirmed; cleanup mutation must not run.",
                "logic://project/info",
                nil,
                ["has_document=false"],
                "cache_fresh"
            ))
        }
        if snapshot.axOccluded {
            findings.append(finding(
                "ax_occluded",
                .warn,
                "system",
                "Accessibility readback is currently occluded by a modal or floating window.",
                "logic://system/health",
                nil,
                ["ax_occluded=true"],
                "cache_stale"
            ))
        }
        if project.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || project.filePath == nil {
            findings.append(finding(
                "project_identity_ambiguous",
                .warn,
                "project",
                "Project identity is incomplete; confirm the intended session before cleanup.",
                "logic://project/info",
                nil,
                ["name=\(project.name.isEmpty ? "<empty>" : project.name)", "file_path=\(project.filePath ?? "<nil>")"],
                project.provenance
            ))
        }
        if snapshot.transport.lastUpdated <= .distantPast {
            findings.append(finding(
                "transport_unread",
                .warn,
                "transport",
                "Transport state has not been read; export and timing assumptions are unverified.",
                "logic://transport/state",
                nil,
                ["last_updated=<none>"],
                "unavailable"
            ))
        }
        if snapshot.tracksFetchedAt <= .distantPast {
            findings.append(finding(
                "track_inventory_unread",
                .warn,
                "tracks",
                "Track inventory has not been read from the current session.",
                "logic://tracks",
                nil,
                ["track_count=\(tracks.total)"],
                "unavailable"
            ))
        } else if tracks.total == 0 {
            findings.append(finding(
                "track_inventory_empty",
                .info,
                "tracks",
                "Track inventory is empty; this may be a blank project or an incomplete readback.",
                "logic://tracks",
                nil,
                ["track_count=0"],
                tracks.freshness.provenance
            ))
        }
        if !tracks.duplicateNames.isEmpty {
            for group in tracks.duplicateNames {
                findings.append(finding(
                    "duplicate_track_names_\(slug(group.name))",
                    .warn,
                    "tracks",
                    "Duplicate track name detected: \(group.name).",
                    "logic://tracks",
                    group.indices.map(String.init).joined(separator: ","),
                    ["name=\(group.name)", "indices=\(group.indices.map(String.init).joined(separator: ","))"],
                    tracks.freshness.provenance
                ))
            }
        }
        if !tracks.unnamedTrackIndices.isEmpty {
            findings.append(finding(
                "unnamed_or_placeholder_tracks",
                .warn,
                "tracks",
                "Unnamed or placeholder track names need confirmation before handoff.",
                "logic://tracks",
                tracks.unnamedTrackIndices.map(String.init).joined(separator: ","),
                ["indices=\(tracks.unnamedTrackIndices.map(String.init).joined(separator: ","))"],
                tracks.freshness.provenance
            ))
        }

        let emptyTracks = emptyTrackIndices(snapshot)
        if snapshot.regionsFetchedAt <= .distantPast {
            findings.append(finding(
                "region_inventory_unread",
                .info,
                "regions",
                "Region inventory is unavailable, so empty-track findings are intentionally withheld.",
                "logic://project/audit",
                nil,
                ["regions_fetched_at=<none>"],
                "unavailable"
            ))
        } else if !emptyTracks.isEmpty {
            findings.append(finding(
                "empty_tracks_detected",
                .info,
                "tracks",
                "Tracks with no cached regions were detected; review manually before deleting or hiding anything.",
                "logic://tracks/{index}/regions",
                emptyTracks.map(String.init).joined(separator: ","),
                ["indices=\(emptyTracks.map(String.init).joined(separator: ","))"],
                "cache_fresh"
            ))
        }

        if !tracks.soloedIndices.isEmpty {
            findings.append(finding(
                "soloed_tracks_present",
                .warn,
                "export",
                "Soloed tracks can make exports omit unintended material.",
                "logic://tracks",
                tracks.soloedIndices.map(String.init).joined(separator: ","),
                ["soloed_indices=\(tracks.soloedIndices.map(String.init).joined(separator: ","))"],
                tracks.freshness.provenance
            ))
        }
        if !tracks.armedIndices.isEmpty {
            findings.append(finding(
                "armed_tracks_present",
                .warn,
                "export",
                "Record-armed tracks should be reviewed before cleanup or export.",
                "logic://tracks",
                tracks.armedIndices.map(String.init).joined(separator: ","),
                ["armed_indices=\(tracks.armedIndices.map(String.init).joined(separator: ","))"],
                tracks.freshness.provenance
            ))
        }

        let mutedSoloed = snapshot.tracks.filter { $0.isMuted && $0.isSoloed }.map(\.id)
        if !mutedSoloed.isEmpty {
            findings.append(finding(
                "muted_and_soloed_tracks",
                .warn,
                "tracks",
                "Some tracks are both muted and soloed, which is ambiguous for cleanup and export.",
                "logic://tracks",
                mutedSoloed.map(String.init).joined(separator: ","),
                ["indices=\(mutedSoloed.map(String.init).joined(separator: ","))"],
                tracks.freshness.provenance
            ))
        }
        let mutedArmed = snapshot.tracks.filter { $0.isMuted && $0.isArmed }.map(\.id)
        if !mutedArmed.isEmpty {
            findings.append(finding(
                "muted_and_armed_tracks",
                .warn,
                "tracks",
                "Some tracks are muted while record-armed; confirm intent before recording or cleanup.",
                "logic://tracks",
                mutedArmed.map(String.init).joined(separator: ","),
                ["indices=\(mutedArmed.map(String.init).joined(separator: ","))"],
                tracks.freshness.provenance
            ))
        }

        if snapshot.markersFetchedAt <= .distantPast {
            findings.append(finding(
                "marker_inventory_unread",
                .info,
                "markers",
                "Marker structure has not been read.",
                "logic://markers",
                nil,
                ["markers_fetched_at=<none>"],
                "unavailable"
            ))
        } else if snapshot.markers.isEmpty {
            findings.append(finding(
                "marker_structure_missing",
                .info,
                "markers",
                "No markers are present in the cached session view.",
                "logic://markers",
                nil,
                ["marker_count=0"],
                "cache_fresh"
            ))
        }

        if mixer.dataSource == "mixer_not_visible" || mixer.dataSource == "cache_stale" {
            findings.append(finding(
                "mixer_inventory_not_fresh",
                .warn,
                "mixer",
                "Mixer and plugin-slot inventory is not fresh enough for safe cleanup mutation.",
                "logic://mixer",
                nil,
                ["data_source=\(mixer.dataSource)"],
                mixer.freshness.provenance
            ))
        }
        if !mixer.pluginReadErrors.isEmpty {
            findings.append(finding(
                "plugin_inventory_errors",
                .warn,
                "plugins",
                "One or more plugin slots reported read errors.",
                "logic://mixer",
                nil,
                mixer.pluginReadErrors,
                mixer.freshness.provenance
            ))
        }
        if !mixer.occupiedPluginSlots.isEmpty {
            findings.append(finding(
                "occupied_plugin_slots_present",
                .info,
                "plugins",
                "Occupied plugin slots are present; cleanup plans must preserve them unless explicitly confirmed.",
                "logic://mixer",
                nil,
                mixer.occupiedPluginSlots.map { "track=\($0.trackIndex),slot=\($0.slotIndex),name=\($0.name)" },
                mixer.freshness.provenance
            ))
        }

        return findings
    }

    private static func cleanupPlanSteps(
        snapshot: Snapshot,
        findings: [Finding],
        duplicateNames: [DuplicateNameGroup],
        unnamedTrackIndices: [Int],
        emptyTrackIndices: [Int]
    ) -> [CleanupPlanStep] {
        var steps: [CleanupPlanStep] = [
            CleanupPlanStep(
                id: "read_audit_snapshot",
                targetIdentifier: "session",
                proposedOperation: "Review logic://project/audit before any mutation.",
                rationale: "Cleanup must start from explicit evidence and provenance labels.",
                riskLevel: .low,
                requiredConfirmation: "none",
                expectedReadback: "schema=\(auditSchema), read_only=true, findings[] present",
                rollbackOrRecovery: "No rollback required; read-only.",
                stopCondition: "Stop if audit status is failed or any required evidence is unavailable.",
                supportedByCurrentTools: true,
                mutatesProject: false,
                tool: nil,
                command: nil
            ),
        ]

        for group in duplicateNames {
            steps.append(CleanupPlanStep(
                id: "rename_duplicate_\(slug(group.name))",
                targetIdentifier: "tracks:\(group.indices.map(String.init).joined(separator: ","))",
                proposedOperation: "Rename duplicate tracks with explicit user-provided names.",
                rationale: "Duplicate names make later target selection and handoff ambiguous.",
                riskLevel: .medium,
                requiredConfirmation: "L1 + explicit new name per track",
                expectedReadback: "logic://tracks shows unique names for the same indices",
                rollbackOrRecovery: "Rename each track back to its previous name from the audit evidence.",
                stopCondition: "Stop on State B/C, stale track inventory, or name readback mismatch.",
                supportedByCurrentTools: true,
                mutatesProject: true,
                tool: "logic_tracks",
                command: "rename"
            ))
        }

        if !unnamedTrackIndices.isEmpty {
            steps.append(CleanupPlanStep(
                id: "rename_unnamed_or_placeholder_tracks",
                targetIdentifier: "tracks:\(unnamedTrackIndices.map(String.init).joined(separator: ","))",
                proposedOperation: "Rename unnamed or placeholder tracks with explicit user-provided names.",
                rationale: "Placeholder track names are unsafe targets for later automated operations.",
                riskLevel: .medium,
                requiredConfirmation: "L1 + explicit new name per track",
                expectedReadback: "logic://tracks shows non-empty, non-placeholder names",
                rollbackOrRecovery: "Rename each track back to its previous name from audit evidence.",
                stopCondition: "Stop on State B/C, stale track inventory, or name readback mismatch.",
                supportedByCurrentTools: true,
                mutatesProject: true,
                tool: "logic_tracks",
                command: "rename"
            ))
        }

        if !emptyTrackIndices.isEmpty {
            steps.append(CleanupPlanStep(
                id: "review_empty_tracks_no_delete",
                targetIdentifier: "tracks:\(emptyTrackIndices.map(String.init).joined(separator: ","))",
                proposedOperation: "Review empty tracks; do not delete by default.",
                rationale: "Empty-track detection is deterministic only for cached regions and may miss hidden or unfetched content.",
                riskLevel: .low,
                requiredConfirmation: "manual review; deletion intentionally not proposed",
                expectedReadback: "caller records keep/hide/delete intent outside this read-only milestone",
                rollbackOrRecovery: "No project mutation is performed by this step.",
                stopCondition: "Stop if region inventory is stale or unavailable.",
                supportedByCurrentTools: false,
                mutatesProject: false,
                tool: nil,
                command: nil
            ))
        }

        let soloed = snapshot.tracks.filter(\.isSoloed).map(\.id)
        if !soloed.isEmpty {
            steps.append(toggleStep(
                id: "clear_solo_states",
                target: soloed,
                operation: "Set solo=false for explicitly confirmed tracks.",
                command: "solo",
                rationale: "Soloed tracks can alter export/handoff readiness."
            ))
        }

        let armed = snapshot.tracks.filter(\.isArmed).map(\.id)
        if !armed.isEmpty {
            steps.append(toggleStep(
                id: "clear_arm_states",
                target: armed,
                operation: "Set arm=false for explicitly confirmed tracks.",
                command: "arm",
                rationale: "Record-armed tracks should not be left armed before cleanup or export."
            ))
        }

        if findings.contains(where: { $0.id == "marker_structure_missing" }) {
            steps.append(CleanupPlanStep(
                id: "plan_marker_structure",
                targetIdentifier: "markers",
                proposedOperation: "Draft marker names/positions before creating any marker.",
                rationale: "A marker plan improves handoff readiness, but marker writes must be explicit.",
                riskLevel: .medium,
                requiredConfirmation: "L1 + marker name and position per marker",
                expectedReadback: "logic://markers shows created markers with canonical positions",
                rollbackOrRecovery: "Manual recovery in Logic marker list; no automatic deletion in this milestone.",
                stopCondition: "Stop if marker readback is stale, non-canonical, or unavailable.",
                supportedByCurrentTools: true,
                mutatesProject: true,
                tool: "logic_navigate",
                command: "create_marker"
            ))
        }

        if findings.contains(where: { $0.id == "mixer_inventory_not_fresh" }) {
            steps.append(CleanupPlanStep(
                id: "refresh_mixer_inventory",
                targetIdentifier: "mixer",
                proposedOperation: "Refresh cache after making the Mixer visible, then re-run audit.",
                rationale: "Mixer/plugin cleanup decisions require fresh slot provenance.",
                riskLevel: .low,
                requiredConfirmation: "none",
                expectedReadback: "logic://mixer data_source becomes ax_poll",
                rollbackOrRecovery: "No rollback required; read-only/cache refresh.",
                stopCondition: "Stop if data_source remains mixer_not_visible or cache_stale.",
                supportedByCurrentTools: true,
                mutatesProject: false,
                tool: "logic_system",
                command: "refresh_cache"
            ))
        }

        return steps
    }

    private static func toggleStep(
        id: String,
        target: [Int],
        operation: String,
        command: String,
        rationale: String
    ) -> CleanupPlanStep {
        CleanupPlanStep(
            id: id,
            targetIdentifier: "tracks:\(target.map(String.init).joined(separator: ","))",
            proposedOperation: operation,
            rationale: rationale,
            riskLevel: .medium,
            requiredConfirmation: "L1 + explicit track indices",
            expectedReadback: "logic://tracks shows \(command)=false for the same indices",
            rollbackOrRecovery: "Restore previous state from audit evidence if the change was not intended.",
            stopCondition: "Stop on State B/C, stale track inventory, or readback mismatch.",
            supportedByCurrentTools: true,
            mutatesProject: true,
            tool: "logic_tracks",
            command: command
        )
    }

    private static func duplicateNameGroups(_ tracks: [TrackState]) -> [DuplicateNameGroup] {
        let grouped = Dictionary(grouping: tracks) {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        return grouped.compactMap { key, tracks in
            guard !key.isEmpty, tracks.count > 1 else { return nil }
            let displayName = tracks.first?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? key
            return DuplicateNameGroup(name: displayName, indices: tracks.map(\.id).sorted())
        }
        .sorted { $0.name < $1.name }
    }

    private static func emptyTrackIndices(_ snapshot: Snapshot) -> [Int] {
        guard snapshot.regionsFetchedAt > .distantPast else { return [] }
        let tracksWithRegions = Set(snapshot.regions.map(\.trackIndex))
        return snapshot.tracks
            .filter { !tracksWithRegions.contains($0.id) }
            .map(\.id)
            .sorted()
    }

    private static func occupiedPluginSlots(_ strips: [ChannelStripState]) -> [PluginSlotEvidence] {
        var slots: [PluginSlotEvidence] = []
        for strip in strips {
            for plugin in strip.plugins {
                slots.append(
                    PluginSlotEvidence(trackIndex: strip.trackIndex, slotIndex: plugin.index, name: plugin.name)
                )
            }
        }
        return slots.sorted { lhs, rhs in
            lhs.trackIndex == rhs.trackIndex ? lhs.slotIndex < rhs.slotIndex : lhs.trackIndex < rhs.trackIndex
        }
    }

    private static func exportReadiness(from findings: [Finding]) -> ExportReadiness {
        let blockers = findings.filter { $0.severity == .blocker }.map(\.id).sorted()
        let warnings = findings.filter { $0.category == "export" || $0.id == "project_identity_ambiguous" }
            .map(\.id)
            .sorted()
        let status = !blockers.isEmpty ? "blocked" : (warnings.isEmpty ? "review_ready" : "review_required")
        return ExportReadiness(status: status, blockers: blockers, warnings: warnings)
    }

    private static func reportStatus(from findings: [Finding]) -> Status {
        if findings.contains(where: { $0.severity == .blocker }) { return .failed }
        if findings.contains(where: { $0.severity == .warn }) { return .degraded }
        return .ok
    }

    private static func freshness(fetchedAt: Date, fallbackProvenance: String, now: Date) -> EvidenceFreshness {
        guard fetchedAt > .distantPast else {
            return EvidenceFreshness(
                available: false,
                provenance: "unavailable",
                fetchedAt: nil,
                cacheAgeSec: nil,
                stale: true
            )
        }
        let age = max(0, now.timeIntervalSince(fetchedAt))
        return EvidenceFreshness(
            available: true,
            provenance: age > staleThresholdSeconds ? "cache_stale" : fallbackProvenance,
            fetchedAt: ISO8601DateFormatter.cacheFormatter.string(from: fetchedAt),
            cacheAgeSec: rounded(age),
            stale: age > staleThresholdSeconds
        )
    }

    private static func finding(
        _ id: String,
        _ severity: Severity,
        _ category: String,
        _ summary: String,
        _ resource: String,
        _ target: String?,
        _ values: [String],
        _ provenance: String
    ) -> Finding {
        Finding(
            id: id,
            severity: severity,
            category: category,
            summary: summary,
            evidence: FindingEvidence(resource: resource, target: target, values: values),
            provenance: provenance
        )
    }

    private static func slug(_ value: String) -> String {
        var output = ""
        var lastWasDash = false
        for scalar in value.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                output.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash {
                output.append("-")
                lastWasDash = true
            }
        }
        let collapsed = output.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return collapsed.isEmpty ? "unnamed" : collapsed
    }

    private static func rounded(_ value: Double) -> Double {
        (value * 1000.0).rounded() / 1000.0
    }
}

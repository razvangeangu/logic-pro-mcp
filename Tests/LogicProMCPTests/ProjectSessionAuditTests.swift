import Foundation
import MCP
import Testing
@testable import LogicProMCP

@Test func testProjectSessionAuditFindingsAndCleanupPlanAreDeterministic() async throws {
    let cache = StateCache()

    var project = ProjectInfo()
    project.name = "Messy Session"
    project.filePath = "/tmp/Messy Session.logicx"
    project.trackCount = 3
    project.source = "ax_live"
    await cache.updateProject(project)

    var transport = TransportState()
    transport.tempo = 126
    transport.lastUpdated = Date()
    await cache.updateTransport(transport)

    var kickA = TrackState(id: 0, name: "Kick", type: .audio)
    kickA.isSoloed = true
    var kickB = TrackState(id: 1, name: "Kick", type: .audio)
    kickB.isMuted = true
    kickB.isSoloed = true
    var unnamed = TrackState(id: 2, name: "", type: .softwareInstrument)
    unnamed.isArmed = true
    unnamed.placeholder = true
    await cache.updateTracks([kickA, kickB, unnamed])

    await cache.updateRegions([
        RegionState(
            id: "0:1:5:Kick",
            name: "Kick",
            trackIndex: 0,
            startPosition: "1 1 1 1",
            endPosition: "5 1 1 1",
            length: "4 0 0 0"
        ),
    ])
    await cache.updateMarkers([])

    var strip = ChannelStripState(trackIndex: 0)
    strip.plugins = [PluginSlotState(index: 0, name: "Channel EQ", isBypassed: false)]
    strip.pluginsSource = "ax"
    await cache.updateChannelStrips([strip])

    let report = await ProjectSessionAudit.buildAudit(cache: cache)

    #expect(report.schema == "logic_pro_mcp_project_audit.v1")
    #expect(report.readOnly)
    #expect(report.status == .degraded)
    #expect(report.evidence.tracks.total == 3)
    #expect(report.evidence.mixer.occupiedPluginSlots.count == 1)

    let findingIDs = Set(report.findings.map(\.id))
    #expect(findingIDs.contains("duplicate_track_names_kick"))
    #expect(findingIDs.contains("unnamed_or_placeholder_tracks"))
    #expect(findingIDs.contains("empty_tracks_detected"))
    #expect(findingIDs.contains("soloed_tracks_present"))
    #expect(findingIDs.contains("armed_tracks_present"))
    #expect(findingIDs.contains("muted_and_soloed_tracks"))
    #expect(findingIDs.contains("marker_structure_missing"))
    #expect(findingIDs.contains("occupied_plugin_slots_present"))

    let stepIDs = Set(report.cleanupPlan.map(\.id))
    #expect(stepIDs.contains("read_audit_snapshot"))
    #expect(stepIDs.contains("rename_duplicate_kick"))
    #expect(stepIDs.contains("rename_unnamed_or_placeholder_tracks"))
    #expect(stepIDs.contains("review_empty_tracks_no_delete"))
    #expect(stepIDs.contains("clear_solo_states"))
    #expect(stepIDs.contains("clear_arm_states"))
    let emptyTrackReview = try #require(report.cleanupPlan.first { $0.id == "review_empty_tracks_no_delete" })
    #expect(!emptyTrackReview.supportedByCurrentTools)
}

@Test func testProjectAuditAndCleanupPlanResourcesAndCommandsReturnJSON() async throws {
    let cache = StateCache()
    var project = ProjectInfo()
    project.name = "Read Only"
    project.filePath = "/tmp/Read Only.logicx"
    project.source = "ax_live"
    await cache.updateProject(project)
    await cache.updateTracks([TrackState(id: 0, name: "Lead", type: .audio)])

    let router = ChannelRouter()
    let auditResource = try await ResourceHandlers.read(uri: "logic://project/audit", cache: cache, router: router)
    let auditJSON = try #require(sharedJSONObject(sharedResourceText(auditResource)))
    #expect(auditJSON["schema"] as? String == "logic_pro_mcp_project_audit.v1")
    #expect(try #require(auditJSON["read_only"] as? Bool))

    let planResource = try await ResourceHandlers.read(uri: "logic://project/cleanup-plan", cache: cache, router: router)
    let planJSON = try #require(sharedJSONObject(sharedResourceText(planResource)))
    #expect(planJSON["schema"] as? String == "logic_pro_mcp_project_cleanup_plan.v1")
    #expect(try #require(planJSON["requires_plan_confirmation"] as? Bool))

    let auditTool = await ProjectDispatcher.handle(command: "audit", params: [:], router: router, cache: cache)
    let auditToolJSON = try #require(sharedJSONObject(sharedToolText(auditTool)))
    #expect(auditToolJSON["schema"] as? String == "logic_pro_mcp_project_audit.v1")

    let planTool = await ProjectDispatcher.handle(command: "cleanup_plan", params: [:], router: router, cache: cache)
    let planToolJSON = try #require(sharedJSONObject(sharedToolText(planTool)))
    #expect(planToolJSON["schema"] as? String == "logic_pro_mcp_project_cleanup_plan.v1")
}

@Test func testProjectAuditWorkflowCatalogEntryIsReadOnlyAndResolved() throws {
    let snapshot = WorkflowSkillCatalog.defaultSnapshot()
    let workflow = try #require(snapshot.workflows.first { $0.id == "logic.workflow.project.audit_cleanup_plan" })

    #expect(snapshot.validation.isValid)
    #expect(workflow.mutationKind == .readOnly)
    #expect(workflow.productionReady)
    #expect(try #require(workflow.dependenciesResolved as Bool?))
    #expect(workflow.allowedResources.contains("logic://project/audit"))
    #expect(workflow.allowedResources.contains("logic://project/cleanup-plan"))
}

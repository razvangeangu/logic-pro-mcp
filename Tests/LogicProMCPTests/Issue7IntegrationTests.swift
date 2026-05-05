import Foundation
import MCP
import Testing
@testable import LogicProMCP

// v3.1.8 (Issue #7) — Cross-resource integration scenarios that exercise the
// regression cases from #3 / #4 / #5 against the new tier-merged resource
// handlers. All scenarios use injected runtimes; no live Logic dependency.

private func makeFileReader(
    bundle: URL?,
    tempo: Double? = 80,
    numerator: Int? = 4,
    denominator: Int? = 4,
    trackCount: Int? = 31
) -> LogicProjectFileReader.Runtime {
    .init(
        currentDocumentPath: { bundle?.path },
        now: { Date(timeIntervalSince1970: 1_700_000_500) },
        readPlistData: { _ in
            var dict: [String: Any] = [:]
            if let t = tempo { dict["BeatsPerMinute"] = t }
            if let n = numerator { dict["SongSignatureNumerator"] = n }
            if let d = denominator { dict["SongSignatureDenominator"] = d }
            if let tc = trackCount { dict["NumberOfTracks"] = tc }
            return try? PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
        },
        mtime: { _ in Date(timeIntervalSince1970: 1_700_000_000) },
        sleep: { _ in }
    )
}

private func ensureBundle(at path: String) -> URL {
    let bundle = URL(fileURLWithPath: path)
    let altDir = bundle
        .appendingPathComponent("Alternatives", isDirectory: true)
        .appendingPathComponent("000", isDirectory: true)
    try? FileManager.default.createDirectory(at: altDir, withIntermediateDirectories: true)
    let leaf = altDir.appendingPathComponent("MetaData.plist")
    if !FileManager.default.fileExists(atPath: leaf.path) {
        try? Data().write(to: leaf)
    }
    return bundle
}

private func parseEnvelope(_ result: ReadResource.Result) throws -> [String: Any] {
    guard !result.contents.isEmpty, let text = result.contents[0].text else {
        throw NSError(domain: "test", code: 0)
    }
    return try (JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]) ?? [:]
}

// MARK: - S1: Tracks panel focused, AX live data populated

@Test
func S1_TracksPanelFocused_AllResourcesLive() async throws {
    let cache = StateCache()

    // Live AX cache: 31 real tracks via poller
    let liveTracks = (0..<31).map {
        TrackState(id: $0, name: "Track-\($0)", type: .audio)
    }
    await cache.updateTracks(liveTracks)

    // Live cache project info (poller wrote real data)
    var liveProject = ProjectInfo()
    liveProject.name = "Lofi-Dreamscape-80"
    liveProject.tempo = 80
    liveProject.timeSignature = "4/4"
    liveProject.trackCount = 31
    liveProject.lastUpdated = Date()
    await cache.updateProject(liveProject)

    // Live cache markers (3 markers from arrange)
    let liveMarkers = [
        MarkerState(id: 0, name: "Intro", position: "1.1.1.1"),
        MarkerState(id: 1, name: "Verse", position: "5.1.1.1"),
        MarkerState(id: 2, name: "Chorus", position: "9.1.1.1"),
    ]
    await cache.updateMarkers(liveMarkers)

    let bundle = ensureBundle(at: NSTemporaryDirectory() + "S1Bundle.logicx")
    let reader = makeFileReader(bundle: bundle, tempo: 999, trackCount: 999)

    // Tracks
    let tracksResult = try await ResourceHandlers.read(
        uri: "logic://tracks", cache: cache, router: ChannelRouter(), fileReader: reader
    )
    let tracksEnv = try parseEnvelope(tracksResult)
    #expect(tracksEnv["source"] as? String == "ax_live")
    let tracksData = tracksEnv["data"] as? [[String: Any]] ?? []
    #expect(tracksData.count == 31)
    #expect(tracksData[0]["name"] as? String == "Track-0")

    // Project info — cache wins, file's BPM 999 must NOT leak through
    let projectResult = try await ResourceHandlers.read(
        uri: "logic://project/info", cache: cache, router: ChannelRouter(), fileReader: reader
    )
    let projectEnv = try parseEnvelope(projectResult)
    let projectData = projectEnv["data"] as? [String: Any] ?? [:]
    #expect(projectData["tempo"] as? Double == 80)
    #expect(projectEnv["source"] as? String == "ax_live" || projectEnv["source"] as? String == "cache")

    // Markers — cache wins
    let markersResult = try await ResourceHandlers.read(
        uri: "logic://markers", cache: cache, router: ChannelRouter(), fileReader: reader
    )
    let markersEnv = try parseEnvelope(markersResult)
    let markersData = markersEnv["data"] as? [[String: Any]] ?? []
    #expect(markersData.count == 3)
    #expect(markersData[0]["name"] as? String == "Intro")
}

// MARK: - S2: Mixer panel focused — cache empty, file fills count

@Test
func S2_MixerPanelFocused_TracksFallbackToFileCount() async throws {
    let cache = StateCache()

    // Cache empty (poller's AX scrape returns empty when Mixer focused — pre-v3.1.8 #3 case)
    // No updateTracks called → cache.getTracks() == []
    // No updateProject called → cache at struct defaults

    let bundle = ensureBundle(at: NSTemporaryDirectory() + "S2Bundle.logicx")
    let reader = makeFileReader(bundle: bundle, tempo: 80, trackCount: 31)

    // Tracks: should emit 31 placeholders
    let tracksResult = try await ResourceHandlers.read(
        uri: "logic://tracks", cache: cache, router: ChannelRouter(), fileReader: reader
    )
    let tracksEnv = try parseEnvelope(tracksResult)
    #expect(tracksEnv["source"] as? String == "project_file")
    let tracksData = tracksEnv["data"] as? [[String: Any]] ?? []
    #expect(tracksData.count == 31)
    #expect(tracksData[0]["name"] as? String == "Track 1")
    #expect((tracksData[0]["placeholder"] as? Bool) == true)

    // Project info: should sourced from file
    let projectResult = try await ResourceHandlers.read(
        uri: "logic://project/info", cache: cache, router: ChannelRouter(), fileReader: reader
    )
    let projectEnv = try parseEnvelope(projectResult)
    let projectData = projectEnv["data"] as? [String: Any] ?? [:]
    #expect(projectData["tempo"] as? Double == 80)
    #expect(projectData["timeSignature"] as? String == "4/4")
    #expect(projectData["trackCount"] as? Int == 31)
    #expect(projectEnv["source"] as? String == "project_file")
    #expect(projectEnv["last_saved_age_sec"] != nil)

    // **G5: cache must NOT be poisoned by tier-merge**
    let cachedTracks = await cache.getTracks()
    #expect(cachedTracks.isEmpty, "G5: cache must remain empty after placeholder emission")

    let cachedProject = await cache.getProject()
    #expect(cachedProject.tempo == 120.0, "cache project must remain at default tempo")
}

// MARK: - S3: No document open

@Test
func S3_NoDocument_AllResourcesDefault() async throws {
    let cache = StateCache()
    let reader = makeFileReader(bundle: nil)

    let tracksResult = try await ResourceHandlers.read(
        uri: "logic://tracks", cache: cache, router: ChannelRouter(), fileReader: reader
    )
    let tracksEnv = try parseEnvelope(tracksResult)
    #expect(tracksEnv["source"] as? String == "default")
    let tracksData = tracksEnv["data"] as? [[String: Any]] ?? []
    #expect(tracksData.isEmpty)

    let projectResult = try await ResourceHandlers.read(
        uri: "logic://project/info", cache: cache, router: ChannelRouter(), fileReader: reader
    )
    let projectEnv = try parseEnvelope(projectResult)
    #expect(projectEnv["source"] as? String == "default")
    let projectData = projectEnv["data"] as? [String: Any] ?? [:]
    #expect(projectData["tempo"] as? Double == 120)

    let markersResult = try await ResourceHandlers.read(
        uri: "logic://markers", cache: cache, router: ChannelRouter(), fileReader: reader
    )
    let markersEnv = try parseEnvelope(markersResult)
    let markersData = markersEnv["data"] as? [[String: Any]] ?? []
    #expect(markersData.isEmpty)
}

// MARK: - S4: cache live tempo diverges from file (unsaved edit)

@Test
func S4_LiveCacheTempoVsStaleFile_CacheWins() async throws {
    let cache = StateCache()

    // Live: user changed tempo to 95 in Logic but didn't save yet
    var live = ProjectInfo()
    live.tempo = 95
    live.timeSignature = "3/4"  // also changed
    live.lastUpdated = Date()
    await cache.updateProject(live)

    let bundle = ensureBundle(at: NSTemporaryDirectory() + "S4Bundle.logicx")
    // File still has the old saved tempo 80 (unsaved change)
    let reader = makeFileReader(bundle: bundle, tempo: 80, numerator: 4, denominator: 4)

    let result = try await ResourceHandlers.read(
        uri: "logic://project/info", cache: cache, router: ChannelRouter(), fileReader: reader
    )
    let envelope = try parseEnvelope(result)
    let data = envelope["data"] as? [String: Any] ?? [:]
    #expect(data["tempo"] as? Double == 95, "cache tempo (live edit) must win, NOT file tempo")
    #expect(data["timeSignature"] as? String == "3/4")
    let source = envelope["source"] as? String
    #expect(source != "project_file", "source must NOT be project_file when cache is fresh")
}

// MARK: - S5: G5 invariant — placeholder emission does not poison cache

@Test
func S5_PlaceholderEmission_CacheUnpoisoned() async throws {
    let cache = StateCache()
    let bundle = ensureBundle(at: NSTemporaryDirectory() + "S5Bundle.logicx")
    let reader = makeFileReader(bundle: bundle, trackCount: 7)

    // Initially empty
    #expect(await cache.getTracks().isEmpty)

    // Read tracks 5 times — each call emits placeholders to caller but NOT cache
    for _ in 0..<5 {
        _ = try await ResourceHandlers.read(
            uri: "logic://tracks", cache: cache, router: ChannelRouter(), fileReader: reader
        )
    }

    let cached = await cache.getTracks()
    #expect(cached.isEmpty, "cache must remain empty across multiple resource calls; got \(cached.count)")

    // Now poller writes legit data
    let liveTracks = (0..<3).map { TrackState(id: $0, name: "Live-\($0)", type: .audio) }
    await cache.updateTracks(liveTracks)

    // Resource read should now reflect live data, not file count
    let result = try await ResourceHandlers.read(
        uri: "logic://tracks", cache: cache, router: ChannelRouter(), fileReader: reader
    )
    let env = try parseEnvelope(result)
    let data = env["data"] as? [[String: Any]] ?? []
    #expect(data.count == 3, "live data wins over file count")
    #expect(env["source"] as? String == "ax_live")
}

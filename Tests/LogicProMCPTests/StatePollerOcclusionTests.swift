import Foundation
import Testing
@testable import LogicProMCP

/// v3.1.4 (#4) — coverage for plugin-window / modal-dialog silent-failure
/// in `StatePoller.pollOnce`. Pre-fix, when both `project.get_info` and
/// `track.get_tracks` returned `.error` while a Logic window was on-screen,
/// the poller incremented `consecutivePollMisses` toward 3 and then cleared
/// the cache (`hasDocument=false` → `clearProjectState()`). For roughly 9s
/// resource reads served stale data with no staleness signal beyond
/// `cache_age_sec`. With the fix, when `runtime.dialogPresent()` reports
/// occlusion the poller preserves the cache and tags `axOccluded=true`.

private func makeOccludedRuntime(
    transportResult: ChannelResult = .success("{}"),
    mixerResult: ChannelResult = .success("[]"),
    markersResult: ChannelResult = .success("[]")
) -> AccessibilityChannel.Runtime {
    .init(
        isTrusted: { true },
        isLogicProRunning: { true },
        appRoot: { nil },
        transportState: { transportResult },
        toggleTransportButton: { _ in .success("{}") },
        setTempo: { _ in .success("{}") },
        setCycleRange: { _ in .success("{}") },
        // Both project + tracks fail — the silent-failure shape we want to
        // exercise. With dialogPresent=true this MUST NOT trigger
        // hasDocument=false / cache wipe.
        tracks: { .error("plugin window has focus") },
        selectedTrack: { .success("{}") },
        selectTrack: { _ in .success("{}") },
        setTrackToggle: { _, _ in .success("{}") },
        renameTrack: { _ in .success("{}") },
        mixerState: { mixerResult },
        channelStrip: { _ in .success("{}") },
        setMixerValue: { _, _ in .success("{}") },
        projectInfo: { .error("plugin window has focus") },
        markers: { markersResult }
    )
}

private func seedCache(_ cache: StateCache) async {
    var project = ProjectInfo()
    project.name = "Live Session"
    project.trackCount = 4
    await cache.updateProject(project)
    await cache.updateTracks([
        TrackState(id: 0, name: "Vox", type: .audio),
        TrackState(id: 1, name: "Drums", type: .audio),
        TrackState(id: 2, name: "Bass", type: .audio),
        TrackState(id: 3, name: "Synth", type: .softwareInstrument),
    ])
}

@Test func testPollerSurvivesPluginWindowOcclusion() async {
    let cache = StateCache()
    await seedCache(cache)
    #expect(await cache.getHasDocument() == true)
    #expect(await cache.getTracks().count == 4)
    #expect(await cache.getAXOccluded() == false)

    let channel = AccessibilityChannel(runtime: makeOccludedRuntime())
    let poller = StatePoller(
        axChannel: channel,
        cache: cache,
        runtime: .init(
            hasVisibleWindow: { true },
            dialogPresent: { true } // plugin/dialog occlusion is in effect
        )
    )

    // Pre-fix: 3 refreshNow calls would tick consecutivePollMisses to 3 and
    // wipe the cache. Post-fix: cache preserved indefinitely while occluded.
    for _ in 0..<5 {
        await poller.refreshNow()
    }

    #expect(await cache.getHasDocument() == true,
            "occluded poll cycles must not clear hasDocument")
    #expect(await cache.getTracks().count == 4,
            "occluded poll cycles must not wipe seeded tracks")
    #expect(await cache.getProject().name == "Live Session",
            "occluded poll cycles must preserve project info")
    #expect(await cache.getAXOccluded() == true,
            "axOccluded flag must be set during sustained occlusion")
}

@Test func testPollerCacheIsTaggedStaleWhenAXOccluded() async {
    let cache = StateCache()
    await seedCache(cache)

    let channel = AccessibilityChannel(runtime: makeOccludedRuntime())
    let poller = StatePoller(
        axChannel: channel,
        cache: cache,
        runtime: .init(
            hasVisibleWindow: { true },
            dialogPresent: { true }
        )
    )

    // Single occluded poll is enough to flip the flag — clients should not
    // have to wait for a threshold to learn that data is stale-by-occlusion.
    await poller.refreshNow()
    #expect(await cache.getAXOccluded() == true)
    // hasDocument intentionally stays true so reads do not 4xx; staleness
    // is signalled via axOccluded + the existing cache_age_sec field.
    #expect(await cache.getHasDocument() == true)
}

@Test func testPollerClearsOccludedFlagWhenAXRecovers() async {
    let cache = StateCache()
    await seedCache(cache)

    // First runtime — occluded.
    let occludedChannel = AccessibilityChannel(runtime: makeOccludedRuntime())
    let occludedPoller = StatePoller(
        axChannel: occludedChannel,
        cache: cache,
        runtime: .init(
            hasVisibleWindow: { true },
            dialogPresent: { true }
        )
    )
    await occludedPoller.refreshNow()
    #expect(await cache.getAXOccluded() == true)

    // Second runtime — AX recovered, polls succeed.
    let recoveredProjectPayload = """
    {"name":"Live Session","sampleRate":48000,"bitDepth":24,"tempo":120,"timeSignature":"4/4","trackCount":4,"filePath":null,"lastUpdated":"2026-04-30T00:00:00Z"}
    """
    let recoveredTracksPayload = """
    [{"id":0,"name":"Vox","type":"audio","isMuted":false,"isSoloed":false,"isArmed":false,"isSelected":false,"volume":0.8,"pan":0.0,"automationMode":"off","color":null}]
    """
    let recoveredChannel = AccessibilityChannel(runtime: .init(
        isTrusted: { true },
        isLogicProRunning: { true },
        appRoot: { nil },
        transportState: { .success("{}") },
        toggleTransportButton: { _ in .success("{}") },
        setTempo: { _ in .success("{}") },
        setCycleRange: { _ in .success("{}") },
        tracks: { .success(recoveredTracksPayload) },
        selectedTrack: { .success("{}") },
        selectTrack: { _ in .success("{}") },
        setTrackToggle: { _, _ in .success("{}") },
        renameTrack: { _ in .success("{}") },
        mixerState: { .success("[]") },
        channelStrip: { _ in .success("{}") },
        setMixerValue: { _, _ in .success("{}") },
        projectInfo: { .success(recoveredProjectPayload) },
        markers: { .success("[]") }
    ))
    let recoveredPoller = StatePoller(
        axChannel: recoveredChannel,
        cache: cache,
        runtime: .init(
            hasVisibleWindow: { true },
            dialogPresent: { false } // dialog/plugin focus released
        )
    )
    await recoveredPoller.refreshNow()
    #expect(await cache.getAXOccluded() == false,
            "axOccluded must clear once polls recover")
    #expect(await cache.getHasDocument() == true)
}

@Test func testPollerStillClearsCacheWhenDocumentTrulyClosesWithoutOcclusion() async {
    // Regression guard: the v3.1.4 fix must NOT extend the failure threshold
    // for the genuinely-closed-document path (no dialog, no plugin window —
    // user closed the project). 3 consecutive misses must still clear.
    let cache = StateCache()
    await seedCache(cache)

    let channel = AccessibilityChannel(runtime: makeOccludedRuntime())
    let poller = StatePoller(
        axChannel: channel,
        cache: cache,
        runtime: .init(
            hasVisibleWindow: { true },
            dialogPresent: { false } // no occlusion — failures are real
        )
    )

    await poller.refreshNow()
    await poller.refreshNow()
    #expect(await cache.getHasDocument() == true,
            "first 2 misses must not clear (existing failureThreshold=3 contract)")

    await poller.refreshNow()
    #expect(await cache.getHasDocument() == false,
            "3rd consecutive miss without occlusion must clear, as before")
    #expect(await cache.getAXOccluded() == false,
            "axOccluded must be false when document is genuinely closed")
}

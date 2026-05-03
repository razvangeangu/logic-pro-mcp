import Foundation
import Testing
@testable import LogicProMCP

/// v3.1.1 (P1-3) — coverage for the consecutive-empty-poll guard in
/// `StateCache.updateTracks`. Modal dialogs over the arrange area
/// transiently produce an empty AX subtree; without the guard the cache
/// flips to "empty project" for one poll cycle and silently breaks every
/// track tool. The guard absorbs the first two empties and only commits an
/// empty list once the third lands.

@Test func testEmptyPollDoesNotImmediatelyClearTracks() async {
    let cache = StateCache()
    // Seed: hasDocument true (default) + a populated track list.
    let seeded = [
        TrackState(id: 0, name: "Vox", type: .audio),
        TrackState(id: 1, name: "Drums", type: .audio),
    ]
    await cache.updateTracks(seeded)
    #expect(await cache.getTracks().count == 2)
    #expect(await cache.getConsecutiveEmptyPolls() == 0)

    // First empty poll — must be absorbed; counter ticks to 1.
    await cache.updateTracks([])
    #expect(await cache.getTracks().count == 2, "first empty must not clear cache")
    #expect(await cache.getConsecutiveEmptyPolls() == 1)

    // Second empty poll — still absorbed; counter ticks to 2.
    await cache.updateTracks([])
    #expect(await cache.getTracks().count == 2, "second empty must not clear cache")
    #expect(await cache.getConsecutiveEmptyPolls() == 2)
}

@Test func testEmptyPollClearsAfterThreshold() async {
    let cache = StateCache()
    let seeded = [TrackState(id: 0, name: "T1", type: .audio)]
    await cache.updateTracks(seeded)

    // 3 consecutive empties — third one must commit.
    await cache.updateTracks([])
    await cache.updateTracks([])
    await cache.updateTracks([])
    #expect(await cache.getTracks().isEmpty, "third empty poll must commit")
    // Counter resets to 0 after the threshold commit so a follow-up
    // populate→empty cycle restarts the absorption window.
    #expect(await cache.getConsecutiveEmptyPolls() == 0)
}

@Test func testNonEmptyPollResetsCounter() async {
    let cache = StateCache()
    await cache.updateTracks([TrackState(id: 0, name: "T1", type: .audio)])
    await cache.updateTracks([])
    #expect(await cache.getConsecutiveEmptyPolls() == 1)

    // A non-empty poll mid-flight resets the counter so the next empty
    // restarts the absorption window from 0.
    await cache.updateTracks([
        TrackState(id: 0, name: "T1", type: .audio),
        TrackState(id: 1, name: "T2", type: .audio),
    ])
    #expect(await cache.getConsecutiveEmptyPolls() == 0)
    #expect(await cache.getTracks().count == 2)
}

@Test func testEmptyPollGuardSkippedWhenNoDocumentOpen() async {
    let cache = StateCache()
    // hasDocument = false (no project open). Empty list is the truth and
    // must commit immediately — the guard only protects against transient
    // dialog occlusion of an open project.
    await cache.updateDocumentState(false)
    await cache.updateTracks([])
    #expect(await cache.getTracks().isEmpty)
    #expect(await cache.getConsecutiveEmptyPolls() == 0)
}

@Test func testEmptyPollGuardSkippedWhenCacheAlreadyEmpty() async {
    let cache = StateCache()
    // Pristine cache: tracks already empty. An empty poll is a no-op
    // without touching the counter — there is nothing to protect.
    await cache.updateTracks([])
    #expect(await cache.getTracks().isEmpty)
    #expect(await cache.getConsecutiveEmptyPolls() == 0)
}

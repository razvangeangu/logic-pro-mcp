import Foundation
import Testing
@testable import LogicProMCP

// T8 — TrackDispatcher description must surface the BREAKING channel-index
// migration (record_sequence `notes` ch field, 0-based → 1-based since v3.1.6).
// PRD: issue1-keycmd-port-routing AC-10 / §3 AC-2.6 BREAKING #2
//
// Background: NoteSequenceParser changed semantics in v3.1.6 — `notes` 5th
// field `ch` is now 1-based (Ch1=1, was Ch1=0). Callers that scripted against
// pre-v3.1.6 must shift values by +1. The tool description is the durable
// contract; this test locks the migration breadcrumb in.

@Suite("TrackDispatcher tool description contract")
struct TrackDispatcherDescriptionTests {

    @Test("description includes 1-based channel breadcrumb for record_sequence")
    func testTrackDispatcherDescriptionIncludesChannelInfo() {
        let description = TrackDispatcher.tool.description ?? ""

        // The migration breadcrumb must be discoverable via tools/list.
        #expect(
            description.contains("1-based"),
            "TrackDispatcher.tool.description must mention 1-based channel convention (BREAKING since v3.1.6)"
        )
        #expect(
            description.contains("v3.1.6") || description.contains("since v3.1"),
            "TrackDispatcher.tool.description must reference the v3.1.6 BREAKING change for `notes` ch field"
        )
    }
}

import Foundation
import Testing
@testable import LogicProMCP

/// #60 (Phase 3): the read-only heuristic token bags that classify which AX
/// container is the marker ruler / the transport-control bar are now centralized
/// in `AXLocalePolicy` instead of inline literals. These deterministic EN+KO
/// tests pin the token coverage so a future edit can't silently drop a locale.
/// They are read-only classifiers — no State-A success is gated on them.
@Suite("Issue60 locale phase 3 token bags")
struct Issue60LocalePhase3Tests {
    @Test("marker container keywords cover EN + KO")
    func markerKeywords() {
        let labels = AXLocalePolicy.markerContainerKeywords.labels
        #expect(labels.contains("marker"))
        #expect(labels.contains("마커"))
    }

    @Test("transport container metadata covers EN + KO")
    func transportMetadata() {
        let labels = AXLocalePolicy.transportContainerMetadata.labels
        #expect(labels.contains("transport"))
        #expect(labels.contains("control bar"))
        #expect(labels.contains("컨트롤 막대"))
    }

    @Test("transport control keywords preserve the full EN + KO token set")
    func transportControlKeywords() {
        let labels = Set(AXLocalePolicy.transportContainerControlKeywords.labels)
        // The exact set the inline literal carried (order-independent).
        let expected: Set<String> = [
            "play", "stop", "record", "cycle", "loop", "metronome", "rewind", "forward",
            "재생", "녹음", "사이클", "메트로놈", "클릭",
        ]
        #expect(labels == expected, "token set drifted: \(labels.symmetricDifference(expected))")
    }

    @Test("transport slider hint tokens cover EN + KO")
    func transportSliderHints() {
        let labels = Set(AXLocalePolicy.transportSliderHints.labels)
        let expected: Set<String> = ["tempo", "bpm", "position", "템포", "재생헤드 위치", "마디", "비트"]
        #expect(labels == expected, "token set drifted: \(labels.symmetricDifference(expected))")
    }

    @Test("containsAny matches both EN and KO control-bar metadata (classifier semantics)")
    func containsAnyEnKo() {
        // The classifier scans an already-lowercased aggregate string.
        #expect(AXLocalePolicy.transportContainerMetadata.containsAny(in: "group transport bar"))
        #expect(AXLocalePolicy.transportContainerMetadata.containsAny(in: "그룹 컨트롤 막대"))
        #expect(!AXLocalePolicy.transportContainerMetadata.containsAny(in: "mixer strip"))
    }

    @Test("every Phase 3 token bag carries at least one Korean variant")
    func everyBagHasKorean() {
        let bags: [(String, AXLocalePolicy.LabelSet)] = [
            ("markerContainerKeywords", AXLocalePolicy.markerContainerKeywords),
            ("transportContainerMetadata", AXLocalePolicy.transportContainerMetadata),
            ("transportContainerControlKeywords", AXLocalePolicy.transportContainerControlKeywords),
            ("transportSliderHints", AXLocalePolicy.transportSliderHints),
        ]
        for (name, bag) in bags {
            let hasKorean = bag.labels.contains { $0.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) } }
            #expect(hasKorean, "\(name) must carry a Korean variant for KO-locale coverage")
        }
    }
}

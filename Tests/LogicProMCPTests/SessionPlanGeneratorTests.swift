import Foundation
import MCP
import Testing
@testable import LogicProMCP

private func sessionPlanResourceObject(_ uri: String) async throws -> [String: Any] {
    let result = try await ResourceHandlers.read(uri: uri, cache: StateCache(), router: ChannelRouter())
    return try #require(sharedJSONObject(sharedResourceText(result)))
}

private func sessionPlanResourceThrows(_ uri: String) async -> Bool {
    do {
        _ = try await ResourceHandlers.read(uri: uri, cache: StateCache(), router: ChannelRouter())
        return false
    } catch {
        return true
    }
}

@Suite("Session plan generator — parsing")
struct SessionPlanParsingTests {
    @Test("extracts tempo, key, scale, genre, and bar count from funk prompt")
    func extractsFunkIntent() {
        let intent = SessionPlanGenerator.parseIntent(prompt: "16-bar funk in E minor at 110 BPM with drums, bass, guitar, and keys")

        #expect(intent.tempoBPM == 110)
        #expect(intent.key == "E")
        #expect(intent.scale == "minor")
        #expect(intent.genre == "funk")
        #expect(intent.totalBars == 16)
        #expect(intent.timeSignature == "4/4")
        #expect(intent.confidence["tempo_bpm"] == "prompt")
    }

    @Test("extracts flat major keys and lo-fi defaults")
    func extractsFlatMajorIntent() {
        let intent = SessionPlanGenerator.parseIntent(prompt: "8-bar lo-fi loop at 75 BPM in Bb major")

        #expect(intent.tempoBPM == 75)
        #expect(intent.key == "Bb")
        #expect(intent.scale == "major")
        #expect(intent.genre == "lo-fi")
        #expect(intent.totalBars == 8)
    }

    @Test("uses genre defaults when prompt omits tempo")
    func genreDefaultTempo() {
        let intent = SessionPlanGenerator.parseIntent(prompt: "32-bar cinematic cue in D minor with strings, brass, and percussion")

        #expect(intent.tempoBPM == 90)
        #expect(intent.confidence["tempo_bpm"] == "genre_default")
        #expect(intent.genre == "cinematic")
        #expect(intent.key == "D")
        #expect(intent.scale == "minor")
    }
}

@Suite("Session plan generator — arrangement")
struct SessionPlanArrangementTests {
    @Test("generates sections for 16-bar and 32-bar prompts")
    func sectionGeneration() {
        let sixteen = SessionPlanGenerator.sections(for: 16, genre: "funk")
        #expect(sixteen.map(\.label) == ["Intro", "Groove A", "Turnaround"])
        #expect(sixteen.last?.startBar == 13)

        let thirtyTwo = SessionPlanGenerator.sections(for: 32, genre: "cinematic")
        #expect(thirtyTwo.map(\.label).contains("Build"))
        #expect(thirtyTwo.last?.startBar == 29)
    }

    @Test("generates deterministic minor and major chord plans")
    func chordPlanGeneration() {
        let minor = SessionPlanGenerator.parseIntent(prompt: "4-bar funk in E minor at 110 BPM")
        let minorChords = SessionPlanGenerator.chordPlan(for: minor).prefix(4).map(\.chord)
        #expect(Array(minorChords) == ["Em", "C", "G", "D"])

        let major = SessionPlanGenerator.parseIntent(prompt: "4-bar lo-fi in Bb major at 75 BPM")
        let majorChords = SessionPlanGenerator.chordPlan(for: major).prefix(4).map(\.chord)
        #expect(Array(majorChords) == ["Bb", "F", "Gm", "Eb"])
    }

    @Test("track plan reports catalog degradation before issue 31 resources are present")
    func trackPlanCatalogDegrades() {
        let plan = SessionPlanGenerator.plan(prompt: "16-bar funk in E minor at 110 BPM with drums, bass, guitar, and keys")

        #expect(plan.instrumentCatalog.status == "degraded_unavailable")
        #expect(plan.trackPlan.contains { $0.role == "drums" && $0.proposedTrackType == "drummer" })
        #expect(plan.trackPlan.contains { $0.role == "guitar" && $0.catalogResource == nil })
        #expect(plan.trackPlan.allSatisfy { $0.suggestionSource == "heuristic_degraded" })
    }
}

@Suite("Session plan generator — safety")
struct SessionPlanSafetyTests {
    @Test("workflow steps validate against the public command surface")
    func proposedCommandsValidate() {
        let plan = SessionPlanGenerator.plan(prompt: "8-bar techno in A minor at 140 BPM with drums, bass, and synth")

        #expect(plan.toolSurfaceValidation.isValid == true)
        #expect(plan.toolSurfaceValidation.checkedCommands.contains("logic_transport.set_tempo"))
        #expect(plan.toolSurfaceValidation.checkedCommands.contains("logic_tracks.create_instrument"))
        #expect(plan.toolSurfaceValidation.checkedCommands.contains("logic_midi.import_file"))
        #expect(plan.workflowSteps.filter(\.mutates).allSatisfy { $0.requiresConfirmationLevel == "L1" })
    }

    @Test("planning-only resource never marks proposed tool steps as executed")
    func noMutationGuarantee() {
        let plan = SessionPlanGenerator.plan(prompt: "16-bar funk in E minor at 110 BPM with drums, bass, guitar, and keys")

        #expect(plan.executionMode == "dry_run_only")
        #expect(plan.workflowSteps.allSatisfy { $0.executed == false })
        #expect(plan.workflowSteps.contains { $0.mutates })
        #expect(plan.nextSafeAction == "review_plan")
    }

    @Test("third-party plugin requests are reported as unsupported")
    func unsupportedThirdPartyReported() {
        let plan = SessionPlanGenerator.plan(prompt: "8-bar house track in A minor with Serum bass")

        #expect(plan.unsupportedOrRiskySteps.contains { $0.operation == "third_party_plugin_or_instrument" })
        #expect(plan.unsupportedOrRiskySteps.contains { $0.operation == "execute_plan" })
    }
}

@Suite("Session plan generator — resources")
struct SessionPlanResourceTests {
    @Test("workflow plan resource returns schema-first dry-run JSON")
    func sessionPlanResource() async throws {
        let resource = try await sessionPlanResourceObject("logic://workflow-plans/session?prompt=16-bar%20funk%20in%20E%20minor%20at%20110%20BPM%20with%20drums%2C%20bass%2C%20guitar%2C%20and%20keys")

        #expect(resource["schema"] as? String == SessionPlanGenerator.schema)
        #expect(resource["execution_mode"] as? String == "dry_run_only")
        #expect((resource["parsed_intent"] as? [String: Any])?["tempo_bpm"] as? Int == 110)
        #expect((resource["sections"] as? [[String: Any]])?.isEmpty == false)
        #expect((resource["chord_plan"] as? [[String: Any]])?.first?["chord"] as? String == "Em")
        #expect((resource["track_plan"] as? [[String: Any]])?.contains { $0["role"] as? String == "bass" } == true)
        #expect((resource["tool_surface_validation"] as? [String: Any])?["is_valid"] as? Bool == true)
        #expect((resource["workflow_steps"] as? [[String: Any]])?.allSatisfy { $0["executed"] as? Bool == false } == true)
    }

    @Test("workflow plan URI routing fails closed on malformed inputs")
    func sessionPlanRoutingFailsClosed() async {
        let malformed = [
            "logic://workflow-plans",
            "logic://workflow-plans/session",
            "logic://workflow-plans?prompt=x",
            "logic://workflow-plans/%73ession?prompt=x",
            "logic://workflow-plans/session?pr%6Fmpt=x",
            "logic://workflow-plans/session?prompt=%ZZ",
            "logic://workflow-plans/session?prompt=x&prompt=y",
            "logic://workflow-plans/session?other=x",
            "logic://workflow-plans/session/extra?prompt=x",
            "logic://workflow-plans/session?prompt=",
            "logic://workflow-plans/session?prompt=x#fragment",
        ]
        for uri in malformed {
            #expect(await sessionPlanResourceThrows(uri), "expected fail-closed read for \(uri)")
        }
    }

    @Test("prompt query is percent-decoded exactly once")
    func promptSingleDecode() async throws {
        let encoded = try await sessionPlanResourceObject("logic://workflow-plans/session?prompt=a%252Bb%20minor%20at%20110%20BPM")
        #expect(encoded["prompt"] as? String == "a%2Bb minor at 110 BPM")

        let plus = try await sessionPlanResourceObject("logic://workflow-plans/session?prompt=a%2Bb%20minor%20at%20110%20BPM")
        #expect(plus["prompt"] as? String == "a+b minor at 110 BPM")
    }
}

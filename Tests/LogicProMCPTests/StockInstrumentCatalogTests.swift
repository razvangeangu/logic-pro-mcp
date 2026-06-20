import Foundation
import MCP
import Testing
@testable import LogicProMCP

private func stockInstrumentResourceObject(_ uri: String) async throws -> [String: Any] {
    let result = try await ResourceHandlers.read(uri: uri, cache: StateCache(), router: ChannelRouter())
    return try #require(sharedJSONObject(sharedResourceText(result)))
}

private func stockInstrumentResourceThrows(_ uri: String) async -> Bool {
    do {
        _ = try await ResourceHandlers.read(uri: uri, cache: StateCache(), router: ChannelRouter())
        return false
    } catch {
        return true
    }
}

private func makeStockInstrumentEntry(
    id: String,
    provenance: [StockInstrumentProvenance],
    supportedActions: [String] = ["planning.recommend_instrument"],
    unsupportedActions: [String] = ["direct_stock_instrument_parameter_write"],
    relatedStockPluginIDs: [String] = ["logic.stock.instrument.alchemy"]
) -> StockInstrumentCatalogEntry {
    StockInstrumentCatalogEntry(
        schema: StockInstrumentCatalogValidator.entrySchema,
        id: id,
        displayName: "Fixture",
        kind: .stockInstrument,
        logicTrackType: .softwareInstrument,
        roles: ["fixture"],
        genreTags: ["fixture"],
        knownFactoryPaths: ["Instrument/Fixture"],
        knownPresets: [],
        relatedStockPluginIDs: relatedStockPluginIDs,
        supportedActions: supportedActions,
        unsupportedActions: unsupportedActions,
        provenance: provenance,
        notes: ["fixture"]
    )
}

@Suite("Stock instrument intelligence — validator")
struct StockInstrumentValidatorTests {
    private let knownPluginIDs: Set<String> = ["logic.stock.instrument.alchemy"]

    @Test("validator rejects duplicate stable IDs")
    func duplicateIDsRejected() {
        let provenance = [
            StockInstrumentProvenance(source: .inferred, confidence: .medium, evidence: ["fixture"]),
        ]
        let entries = [
            makeStockInstrumentEntry(id: "logic.stock.instrument.fixture", provenance: provenance),
            makeStockInstrumentEntry(id: "logic.stock.instrument.fixture", provenance: provenance),
        ]

        let issues = StockInstrumentCatalogValidator.validate(entries, knownStockPluginIDs: knownPluginIDs).issues
        #expect(issues.contains { $0.code == "duplicate_id" })
    }

    @Test("validator rejects malformed stable IDs")
    func invalidIDFormatRejected() {
        let provenance = [
            StockInstrumentProvenance(source: .inferred, confidence: .medium, evidence: ["fixture"]),
        ]
        let badIDs = [
            "logic.stock.instrument.Alchemy",
            "logic.stock.effect.gain",
            "logic.session-player.drummer",
            "logic.stock.instrument.",
        ]
        for badID in badIDs {
            let issues = StockInstrumentCatalogValidator.validate(
                [makeStockInstrumentEntry(id: badID, provenance: provenance)],
                knownStockPluginIDs: knownPluginIDs
            ).issues
            #expect(issues.contains { $0.code == "invalid_id_format" }, "expected invalid_id_format for \(badID)")
        }
    }

    @Test("entries require explicit provenance")
    func missingProvenanceRejected() {
        let entry = makeStockInstrumentEntry(id: "logic.stock.instrument.fixture", provenance: [])

        let issues = StockInstrumentCatalogValidator.validate([entry], knownStockPluginIDs: knownPluginIDs).issues
        #expect(issues.contains { $0.code == "missing_provenance" })
    }

    @Test("documented provenance requires evidence")
    func documentedProvenanceRequiresEvidence() {
        let provenance = [
            StockInstrumentProvenance(source: .documented, confidence: .high, evidence: []),
        ]
        let entry = makeStockInstrumentEntry(id: "logic.stock.instrument.fixture", provenance: provenance)

        let issues = StockInstrumentCatalogValidator.validate([entry], knownStockPluginIDs: knownPluginIDs).issues
        #expect(issues.contains { $0.code == "provenance_missing_evidence" })
    }

    @Test("supported and unsupported action vocabularies are strict")
    func actionConsistencyValidated() {
        let provenance = [
            StockInstrumentProvenance(source: .inferred, confidence: .medium, evidence: ["fixture"]),
        ]
        let entry = makeStockInstrumentEntry(
            id: "logic.stock.instrument.fixture",
            provenance: provenance,
            supportedActions: ["planning.recommend_instrument", "direct_stock_instrument_parameter_write", "bad.action"],
            unsupportedActions: ["direct_stock_instrument_parameter_write", "bad.unsupported"]
        )

        let issues = StockInstrumentCatalogValidator.validate([entry], knownStockPluginIDs: knownPluginIDs).issues
        #expect(issues.contains { $0.code == "unknown_supported_action" })
        #expect(issues.contains { $0.code == "unknown_unsupported_action" })
        #expect(issues.contains { $0.code == "supported_unsupported_overlap" })
    }

    @Test("related stock plugin references cannot dangle")
    func danglingRelatedStockPluginIDsRejected() {
        let provenance = [
            StockInstrumentProvenance(source: .inferred, confidence: .medium, evidence: ["fixture"]),
        ]
        let entry = makeStockInstrumentEntry(
            id: "logic.stock.instrument.fixture",
            provenance: provenance,
            relatedStockPluginIDs: ["logic.stock.instrument.nope"]
        )

        let issues = StockInstrumentCatalogValidator.validate([entry], knownStockPluginIDs: knownPluginIDs).issues
        #expect(issues.contains { $0.code == "dangling_stock_plugin_ref" })
    }
}

@Suite("Stock instrument intelligence — catalog snapshots")
struct StockInstrumentSnapshotTests {
    @Test("stock instrument snapshot is valid and covers core Logic instruments")
    func stockInstrumentSnapshotValid() {
        let snapshot = StockInstrumentCatalog.stockInstrumentSnapshot

        #expect(snapshot.schemaVersion == 1)
        #expect(snapshot.catalogKind == "stock_instruments")
        #expect(snapshot.validation.isValid == true)
        #expect(snapshot.entries.count == snapshot.entryCount)
        #expect(snapshot.entries.count >= 20)
        #expect(snapshot.entries.allSatisfy { $0.id.hasPrefix("logic.stock.instrument.") })
        #expect(snapshot.entries.map(\.id).count == Set(snapshot.entries.map(\.id)).count)
        #expect(snapshot.entries.allSatisfy { !$0.provenance.isEmpty })
        #expect(snapshot.entries.allSatisfy { Set($0.supportedActions).intersection($0.unsupportedActions).isEmpty })
        #expect(snapshot.entries.contains { $0.id == "logic.stock.instrument.alchemy" && $0.kind == .synth })
        #expect(snapshot.entries.contains { $0.id == "logic.stock.instrument.sampler" && $0.kind == .sampler })
        #expect(snapshot.entries.contains { $0.id == "logic.stock.instrument.drum_machine_designer" && $0.kind == .drumMachine })
        #expect(snapshot.entries.contains { $0.id == "logic.stock.instrument.studio_bass" })
    }

    @Test("session player snapshot is valid and marks unsupported direct control")
    func sessionPlayerSnapshotValid() {
        let snapshot = StockInstrumentCatalog.sessionPlayerSnapshot

        #expect(snapshot.schemaVersion == 1)
        #expect(snapshot.catalogKind == "session_players")
        #expect(snapshot.validation.isValid == true)
        #expect(snapshot.entries.count == snapshot.entryCount)
        #expect(snapshot.entries.allSatisfy { $0.id.hasPrefix("logic.session_player.") })
        #expect(snapshot.entries.contains { $0.id == "logic.session_player.drummer" && $0.logicTrackType == .drummer })
        #expect(snapshot.entries.contains { $0.id == "logic.session_player.bass_player" })
        #expect(snapshot.entries.contains { $0.id == "logic.session_player.keyboard_player" })
        #expect(snapshot.entries.contains { $0.id == "logic.session_player.synth_player" })
        #expect(snapshot.entries.allSatisfy { $0.unsupportedActions.contains("session_player_direct_performance_control") || $0.kind == .drummer })
        #expect(snapshot.entries.contains { entry in
            entry.id == "logic.session_player.synth_player" &&
                entry.notes.contains { $0.localizedCaseInsensitiveContains("style") }
        })
    }

    @Test("all related stock plugin IDs resolve against the stock plugin catalog")
    func relatedStockPluginReferencesResolve() {
        let known = Set(StockPluginCatalog.defaultSnapshot(census: .deterministic()).entries.map(\.id))
        let entries = StockInstrumentCatalog.stockInstrumentSnapshot.entries + StockInstrumentCatalog.sessionPlayerSnapshot.entries

        for entry in entries {
            for relatedID in entry.relatedStockPluginIDs {
                #expect(known.contains(relatedID), "dangling related id \(relatedID) in \(entry.id)")
            }
        }
    }

    @Test("search covers name, kind, role, genre, and empty query")
    func stockInstrumentSearch() {
        let snapshot = StockInstrumentCatalog.stockInstrumentSnapshot

        #expect(StockInstrumentCatalog.search(query: "", snapshot: snapshot).count == snapshot.entries.count)
        #expect(StockInstrumentCatalog.search(query: "sampler", snapshot: snapshot).contains { $0.id == "logic.stock.instrument.sampler" })
        #expect(StockInstrumentCatalog.search(query: "pad", snapshot: snapshot).contains { $0.id == "logic.stock.instrument.alchemy" })
        #expect(StockInstrumentCatalog.search(query: "hip hop", snapshot: snapshot).contains { $0.id == "logic.stock.instrument.quick_sampler" })
        #expect(StockInstrumentCatalog.search(query: "does-not-exist", snapshot: snapshot).isEmpty)
    }
}

@Suite("Stock instrument intelligence — resources")
struct StockInstrumentResourceTests {
    @Test("MCP resources expose stock instrument list, detail, search, and Session Player detail")
    func stockInstrumentResources() async throws {
        let list = try await stockInstrumentResourceObject("logic://stock-instruments")
        #expect(list["schema_version"] as? Int == 1)
        #expect(list["catalog_kind"] as? String == "stock_instruments")
        #expect((list["entries"] as? [[String: Any]])?.contains { $0["id"] as? String == "logic.stock.instrument.alchemy" } == true)
        #expect((list["validation"] as? [String: Any])?["is_valid"] as? Bool == true)

        let detail = try await stockInstrumentResourceObject("logic://stock-instruments/logic.stock.instrument.alchemy")
        let detailEntry = try #require(detail["entry"] as? [String: Any])
        #expect(detailEntry["schema"] as? String == StockInstrumentCatalogValidator.entrySchema)
        #expect(detailEntry["id"] as? String == "logic.stock.instrument.alchemy")
        #expect((detailEntry["provenance"] as? [[String: Any]])?.isEmpty == false)

        let search = try await stockInstrumentResourceObject("logic://stock-instruments/search?query=sampler")
        #expect(search["query"] as? String == "sampler")
        #expect((search["entries"] as? [[String: Any]])?.contains { $0["id"] as? String == "logic.stock.instrument.sampler" } == true)

        let sessions = try await stockInstrumentResourceObject("logic://session-players")
        #expect(sessions["catalog_kind"] as? String == "session_players")
        #expect((sessions["entries"] as? [[String: Any]])?.contains { $0["id"] as? String == "logic.session_player.drummer" } == true)

        let drummer = try await stockInstrumentResourceObject("logic://session-players/logic.session_player.drummer")
        #expect((drummer["entry"] as? [String: Any])?["kind"] as? String == "drummer")
    }

    @Test("stock instrument URI routing fails closed on malformed inputs")
    func stockInstrumentRoutingFailsClosed() async {
        let malformed = [
            "logic://stock-instruments?query=alchemy",
            "logic://stock-instruments/%61lchemy",
            "logic://stock-instruments/search?qu%65ry=alchemy",
            "logic://stock-instruments/search?query=%ZZ",
            "logic://stock-instruments/search/extra",
            "logic://stock-instruments/search?other=x",
            "logic://stock-instruments/search?query=alchemy&query=sampler",
            "logic://stock-instruments/logic.stock.instrument.alchemy?x=1",
            "logic://stock-instruments/logic.stock.instrument.alchemy/extra",
            "logic://stock-instruments/unknown.instrument.id",
            "logic://stock-instruments//logic.stock.instrument.alchemy",
            "logic://stock-instruments/logic.stock.instrument.alchemy/",
            "logic://stock-instruments/logic.stock.instrument.alchemy#fragment",
            "logic://stock-instruments/search?query=alchemy#fragment",
        ]
        for uri in malformed {
            #expect(await stockInstrumentResourceThrows(uri), "expected fail-closed read for \(uri)")
        }
    }

    @Test("session player URI routing fails closed on malformed inputs")
    func sessionPlayerRoutingFailsClosed() async {
        let malformed = [
            "logic://session-players?query=drummer",
            "logic://session-players/search?query=drummer",
            "logic://session-players/%64rummer",
            "logic://session-players/logic.session_player.drummer?x=1",
            "logic://session-players/logic.session_player.drummer/extra",
            "logic://session-players/unknown.session.id",
            "logic://session-players//logic.session_player.drummer",
            "logic://session-players/logic.session_player.drummer/",
            "logic://session-players/logic.session_player.drummer#fragment",
        ]
        for uri in malformed {
            #expect(await stockInstrumentResourceThrows(uri), "expected fail-closed read for \(uri)")
        }
    }

    @Test("stock instrument search query is percent-decoded exactly once")
    func searchQuerySingleDecode() async throws {
        let search = try await stockInstrumentResourceObject("logic://stock-instruments/search?query=a%252Bb")
        #expect(search["query"] as? String == "a%2Bb")

        let plus = try await stockInstrumentResourceObject("logic://stock-instruments/search?query=a%2Bb")
        #expect(plus["query"] as? String == "a+b")
    }

    @Test("stock instrument search with empty or missing query returns the full catalog")
    func searchEmptyQueryReturnsAll() async throws {
        let missing = try await stockInstrumentResourceObject("logic://stock-instruments/search")
        let empty = try await stockInstrumentResourceObject("logic://stock-instruments/search?query=")
        let list = try await stockInstrumentResourceObject("logic://stock-instruments")

        let total = (list["entries"] as? [[String: Any]])?.count
        #expect(total != nil)
        #expect((missing["entries"] as? [[String: Any]])?.count == total)
        #expect((empty["entries"] as? [[String: Any]])?.count == total)
    }
}

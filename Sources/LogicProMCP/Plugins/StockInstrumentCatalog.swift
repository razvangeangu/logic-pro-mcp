import Foundation

enum StockInstrumentKind: String, Codable, CaseIterable, Sendable {
    case stockInstrument = "stock_instrument"
    case sessionPlayer = "session_player"
    case drummer
    case sampler
    case synth
    case drumMachine = "drum_machine"
}

enum StockInstrumentTrackType: String, Codable, CaseIterable, Sendable {
    case softwareInstrument = "software_instrument"
    case sessionPlayer = "session_player"
    case drummer
}

enum StockInstrumentProvenanceSource: String, Codable, CaseIterable, Sendable {
    case verifiedLive = "verified_live"
    case filesystemScanned = "filesystem_scanned"
    case documented
    case inferred
}

enum StockInstrumentConfidence: String, Codable, CaseIterable, Sendable {
    case high
    case medium
    case low
}

struct StockInstrumentProvenance: Codable, Sendable, Equatable {
    let source: StockInstrumentProvenanceSource
    let confidence: StockInstrumentConfidence
    let evidence: [String]
}

struct StockInstrumentCatalogEntry: Codable, Sendable, Equatable {
    let schema: String
    let id: String
    let displayName: String
    let kind: StockInstrumentKind
    let logicTrackType: StockInstrumentTrackType
    let roles: [String]
    let genreTags: [String]
    let knownFactoryPaths: [String]
    let knownPresets: [String]
    let relatedStockPluginIDs: [String]
    let supportedActions: [String]
    let unsupportedActions: [String]
    let provenance: [StockInstrumentProvenance]
    let notes: [String]

    enum CodingKeys: String, CodingKey {
        case schema
        case id
        case displayName = "display_name"
        case kind
        case logicTrackType = "logic_track_type"
        case roles
        case genreTags = "genre_tags"
        case knownFactoryPaths = "known_factory_paths"
        case knownPresets = "known_presets"
        case relatedStockPluginIDs = "related_stock_plugin_ids"
        case supportedActions = "supported_actions"
        case unsupportedActions = "unsupported_actions"
        case provenance
        case notes
    }
}

struct StockInstrumentValidationIssue: Codable, Sendable, Equatable {
    let code: String
    let path: String
    let message: String
}

struct StockInstrumentValidationResult: Codable, Sendable, Equatable {
    let isValid: Bool
    let issues: [StockInstrumentValidationIssue]

    enum CodingKeys: String, CodingKey {
        case isValid = "is_valid"
        case issues
    }
}

struct StockInstrumentCatalogSnapshot: Codable, Sendable, Equatable {
    let schemaVersion: Int
    let generatedAt: String
    let catalogKind: String
    let entryCount: Int
    let validation: StockInstrumentValidationResult
    let entries: [StockInstrumentCatalogEntry]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case catalogKind = "catalog_kind"
        case entryCount = "entry_count"
        case validation
        case entries
    }
}

enum StockInstrumentCatalogValidator {
    static let entrySchema = "logic_pro_mcp_instrument_catalog.v1"
    static let idPattern = #"^logic\.(stock\.instrument|session_player)\.[a-z0-9_]+$"#

    static let supportedActionVocabulary: Set<String> = [
        "planning.recommend_instrument",
        "planning.recommend_session_player",
        "logic_tracks.create_instrument",
        "logic_tracks.create_drummer",
        "logic_tracks.set_instrument_after_track_selection",
        "logic_tracks.resolve_path",
        "logic_tracks.list_library",
    ]

    static let unsupportedActionVocabulary: Set<String> = [
        "automatic_factory_preset_load_without_path",
        "claim_live_availability_without_readback",
        "convert_session_player_region_to_midi",
        "direct_chord_track_edit",
        "direct_drummer_performance_parameter_write",
        "direct_stock_instrument_parameter_write",
        "force_session_player_style",
        "session_player_direct_performance_control",
    ]

    static func validate(
        _ entries: [StockInstrumentCatalogEntry],
        knownStockPluginIDs: Set<String>
    ) -> StockInstrumentValidationResult {
        var issues: [StockInstrumentValidationIssue] = []
        var seen = Set<String>()

        for (index, entry) in entries.enumerated() {
            let base = "entries[\(index)]"
            if entry.schema != entrySchema {
                issues.append(issue("invalid_schema", "\(base).schema", "entry schema must be \(entrySchema)"))
            }
            if entry.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(issue("missing_id", "\(base).id", "catalog entry id is required"))
            } else if entry.id.range(of: idPattern, options: .regularExpression) == nil {
                issues.append(issue("invalid_id_format", "\(base).id", "catalog id \(entry.id) must match \(idPattern)"))
            }
            if !seen.insert(entry.id).inserted {
                issues.append(issue("duplicate_id", "\(base).id", "duplicate catalog id \(entry.id)"))
            }
            if entry.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(issue("missing_display_name", "\(base).display_name", "display name is required"))
            }
            if entry.roles.isEmpty {
                issues.append(issue("missing_roles", "\(base).roles", "at least one musical role is required"))
            }
            if entry.provenance.isEmpty {
                issues.append(issue("missing_provenance", "\(base).provenance", "entries require explicit provenance"))
            }
            for (provenanceIndex, provenance) in entry.provenance.enumerated() {
                validateProvenance(provenance, path: "\(base).provenance[\(provenanceIndex)]", issues: &issues)
            }
            let supported = Set(entry.supportedActions)
            let unsupported = Set(entry.unsupportedActions)
            for action in entry.supportedActions where !supportedActionVocabulary.contains(action) {
                issues.append(issue("unknown_supported_action", "\(base).supported_actions", "unknown supported action \(action)"))
            }
            for action in entry.unsupportedActions where !unsupportedActionVocabulary.contains(action) {
                issues.append(issue("unknown_unsupported_action", "\(base).unsupported_actions", "unknown unsupported action \(action)"))
            }
            for overlap in supported.intersection(unsupported).sorted() {
                issues.append(issue(
                    "supported_unsupported_overlap",
                    "\(base).supported_actions",
                    "action \(overlap) cannot be both supported and unsupported"
                ))
            }
            for relatedID in entry.relatedStockPluginIDs where !knownStockPluginIDs.contains(relatedID) {
                issues.append(issue("dangling_stock_plugin_ref", "\(base).related_stock_plugin_ids", "unknown stock plugin id \(relatedID)"))
            }
            if entry.id.hasPrefix("logic.stock.instrument."), entry.logicTrackType != .softwareInstrument {
                issues.append(issue("stock_instrument_track_type", "\(base).logic_track_type", "stock instruments must use software_instrument track type"))
            }
            if entry.id.hasPrefix("logic.session_player."), entry.kind == .stockInstrument || entry.logicTrackType == .softwareInstrument {
                issues.append(issue("session_player_shape", base, "session player entries must not be shaped as stock software instruments"))
            }
        }

        return StockInstrumentValidationResult(isValid: issues.isEmpty, issues: issues)
    }

    private static func validateProvenance(
        _ provenance: StockInstrumentProvenance,
        path: String,
        issues: inout [StockInstrumentValidationIssue]
    ) {
        if provenance.source != .inferred, provenance.evidence.isEmpty {
            issues.append(issue(
                "provenance_missing_evidence",
                path,
                "\(provenance.source.rawValue) provenance requires evidence"
            ))
        }
        if provenance.source == .verifiedLive, provenance.confidence != .high {
            issues.append(issue(
                "verified_live_confidence",
                path,
                "verified_live provenance must be high confidence"
            ))
        }
    }

    private static func issue(_ code: String, _ path: String, _ message: String) -> StockInstrumentValidationIssue {
        StockInstrumentValidationIssue(code: code, path: path, message: message)
    }
}

enum StockInstrumentCatalog {
    static let stockInstrumentSnapshot: StockInstrumentCatalogSnapshot = snapshot(
        kind: "stock_instruments",
        entries: stockInstrumentSeeds
    )

    static let sessionPlayerSnapshot: StockInstrumentCatalogSnapshot = snapshot(
        kind: "session_players",
        entries: sessionPlayerSeeds
    )

    static func entry(
        id: String,
        snapshot: StockInstrumentCatalogSnapshot
    ) -> StockInstrumentCatalogEntry? {
        snapshot.entries.first { $0.id == id }
    }

    static func search(
        query: String,
        snapshot: StockInstrumentCatalogSnapshot = stockInstrumentSnapshot
    ) -> [StockInstrumentCatalogEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return snapshot.entries }
        return snapshot.entries.filter { entry in
            entry.id.lowercased().contains(q) ||
                entry.displayName.lowercased().contains(q) ||
                entry.kind.rawValue.contains(q) ||
                entry.logicTrackType.rawValue.contains(q) ||
                entry.roles.joined(separator: " ").lowercased().contains(q) ||
                entry.genreTags.joined(separator: " ").lowercased().contains(q) ||
                entry.notes.joined(separator: " ").lowercased().contains(q)
        }
    }

    static func snapshot(kind: String, entries: [StockInstrumentCatalogEntry]) -> StockInstrumentCatalogSnapshot {
        let sorted = entries.sorted { $0.id < $1.id }
        let validation = StockInstrumentCatalogValidator.validate(
            sorted,
            knownStockPluginIDs: knownStockPluginIDs
        )
        return StockInstrumentCatalogSnapshot(
            schemaVersion: 1,
            generatedAt: generatedAt,
            catalogKind: kind,
            entryCount: sorted.count,
            validation: validation,
            entries: sorted
        )
    }

    private static let generatedAt = "2026-06-20T00:00:00Z"

    private static let knownStockPluginIDs: Set<String> = Set(
        StockPluginCatalog.defaultSnapshot(census: .deterministic()).entries.map(\.id)
    )

    private static func inferred(_ evidence: String) -> [StockInstrumentProvenance] {
        [
            StockInstrumentProvenance(
                source: .inferred,
                confidence: .medium,
                evidence: [evidence]
            ),
        ]
    }

    private static func documented(_ evidence: [String]) -> [StockInstrumentProvenance] {
        [
            StockInstrumentProvenance(
                source: .documented,
                confidence: .high,
                evidence: evidence
            ),
        ]
    }

    private static func stockInstrument(
        _ idSuffix: String,
        _ displayName: String,
        kind: StockInstrumentKind = .stockInstrument,
        roles: [String],
        genres: [String],
        notes: [String] = []
    ) -> StockInstrumentCatalogEntry {
        let id = "logic.stock.instrument.\(idSuffix)"
        return StockInstrumentCatalogEntry(
            schema: StockInstrumentCatalogValidator.entrySchema,
            id: id,
            displayName: displayName,
            kind: kind,
            logicTrackType: .softwareInstrument,
            roles: roles,
            genreTags: genres,
            knownFactoryPaths: ["Instrument/\(displayName)"],
            knownPresets: [],
            relatedStockPluginIDs: [id],
            supportedActions: [
                "planning.recommend_instrument",
                "logic_tracks.create_instrument",
                "logic_tracks.set_instrument_after_track_selection",
                "logic_tracks.resolve_path",
                "logic_tracks.list_library",
            ],
            unsupportedActions: [
                "automatic_factory_preset_load_without_path",
                "claim_live_availability_without_readback",
                "direct_stock_instrument_parameter_write",
                "session_player_direct_performance_control",
            ],
            provenance: inferred("logic://stock-plugins/\(id)"),
            notes: notes + [
                "Stock instrument identity is cataloged read-only; live menu availability and preset loading still require caller-side verification.",
            ]
        )
    }

    private static func sessionPlayer(
        _ idSuffix: String,
        _ displayName: String,
        kind: StockInstrumentKind,
        trackType: StockInstrumentTrackType,
        roles: [String],
        genres: [String],
        relatedStockPluginIDs: [String],
        supportedActions: [String],
        unsupportedActions: [String],
        provenance: [StockInstrumentProvenance],
        notes: [String]
    ) -> StockInstrumentCatalogEntry {
        StockInstrumentCatalogEntry(
            schema: StockInstrumentCatalogValidator.entrySchema,
            id: "logic.session_player.\(idSuffix)",
            displayName: displayName,
            kind: kind,
            logicTrackType: trackType,
            roles: roles,
            genreTags: genres,
            knownFactoryPaths: [],
            knownPresets: [],
            relatedStockPluginIDs: relatedStockPluginIDs,
            supportedActions: supportedActions,
            unsupportedActions: unsupportedActions,
            provenance: provenance,
            notes: notes
        )
    }

    private static let stockInstrumentSeeds: [StockInstrumentCatalogEntry] = [
        stockInstrument("alchemy", "Alchemy", kind: .synth, roles: ["synth", "pad", "lead", "texture"], genres: ["electronic", "pop", "ambient"]),
        stockInstrument("drum_kit_designer", "Drum Kit Designer", kind: .drumMachine, roles: ["drums", "acoustic kit"], genres: ["rock", "pop", "songwriter"]),
        stockInstrument("drum_machine_designer", "Drum Machine Designer", kind: .drumMachine, roles: ["drums", "electronic kit"], genres: ["electronic", "hip hop", "dance"]),
        stockInstrument("drum_synth", "Drum Synth", kind: .drumMachine, roles: ["drums", "synthetic percussion"], genres: ["electronic", "techno", "experimental"]),
        stockInstrument("efm1", "EFM1", kind: .synth, roles: ["fm synth", "bell", "bass"], genres: ["electronic", "pop"]),
        stockInstrument("es_e", "ES E", kind: .synth, roles: ["ensemble synth", "pad"], genres: ["electronic", "legacy"]),
        stockInstrument("es_m", "ES M", kind: .synth, roles: ["mono synth", "bass"], genres: ["electronic", "legacy"]),
        stockInstrument("es_p", "ES P", kind: .synth, roles: ["poly synth", "pad"], genres: ["electronic", "legacy"]),
        stockInstrument("es1", "ES1", kind: .synth, roles: ["subtractive synth", "bass", "lead"], genres: ["electronic", "dance"]),
        stockInstrument("es2", "ES2", kind: .synth, roles: ["hybrid synth", "lead", "pad"], genres: ["electronic", "pop"]),
        stockInstrument("evoc_20_polysynth", "EVOC 20 PolySynth", kind: .synth, roles: ["vocoder synth", "texture"], genres: ["electronic", "experimental"]),
        stockInstrument("external_instrument", "External Instrument", roles: ["external midi", "hardware instrument"], genres: ["utility"]),
        stockInstrument("playback", "Playback", roles: ["backing playback", "utility"], genres: ["live performance"], notes: ["Availability varies by Logic version."]),
        stockInstrument("quick_sampler", "Quick Sampler", kind: .sampler, roles: ["sampler", "one shot", "loop"], genres: ["electronic", "hip hop", "pop"]),
        stockInstrument("retro_synth", "Retro Synth", kind: .synth, roles: ["synth", "bass", "lead", "pad"], genres: ["electronic", "pop", "retro"]),
        stockInstrument("sample_alchemy", "Sample Alchemy", kind: .sampler, roles: ["sample manipulation", "texture", "pad"], genres: ["ambient", "electronic", "experimental"]),
        stockInstrument("sampler", "Sampler", kind: .sampler, roles: ["sampler", "multisample", "instrument playback"], genres: ["orchestral", "pop", "sound design"]),
        stockInstrument("sculpture", "Sculpture", kind: .synth, roles: ["physical modeling", "pluck", "texture"], genres: ["electronic", "sound design"]),
        stockInstrument("studio_bass", "Studio Bass", roles: ["bass", "session bass"], genres: ["pop", "rock", "songwriter"], notes: ["Introduced in Logic Pro 11; Bass Player commonly uses Studio Bass."]),
        stockInstrument("studio_horns", "Studio Horns", roles: ["horns", "brass section"], genres: ["funk", "soul", "pop"]),
        stockInstrument("studio_strings", "Studio Strings", roles: ["strings", "orchestral section"], genres: ["orchestral", "pop", "film"]),
        stockInstrument("ultrabeat", "Ultrabeat", kind: .drumMachine, roles: ["drum synth", "sequenced drums"], genres: ["electronic", "legacy"]),
        stockInstrument("vintage_b3", "Vintage B3", roles: ["organ", "keys"], genres: ["jazz", "rock", "gospel"]),
        stockInstrument("vintage_clav", "Vintage Clav", roles: ["clavinet", "keys"], genres: ["funk", "soul", "rock"]),
        stockInstrument("vintage_electric_piano", "Vintage Electric Piano", roles: ["electric piano", "keys"], genres: ["soul", "r&b", "pop"]),
        stockInstrument("vintage_mellotron", "Vintage Mellotron", roles: ["mellotron", "choir", "strings"], genres: ["psychedelic", "indie", "film"]),
    ]

    private static let sessionOverview = "https://support.apple.com/guide/logicpro/session-players-overview-lgcpbf624405/mac"
    private static let synthPlayerIntro = "https://support.apple.com/guide/logicpro/intro-to-synth-player-styles-lgcpc49d7e59/mac"
    private static let logic12WhatsNew = "https://support.apple.com/en-ie/guide/logicpro/lgcp4a62a494/mac"

    private static let sessionPlayerSeeds: [StockInstrumentCatalogEntry] = [
        sessionPlayer(
            "drummer",
            "Drummer",
            kind: .drummer,
            trackType: .drummer,
            roles: ["drums", "groove", "arrangement"],
            genres: ["rock", "pop", "electronic", "songwriter"],
            relatedStockPluginIDs: ["logic.stock.instrument.drum_kit_designer", "logic.stock.instrument.drum_machine_designer"],
            supportedActions: ["planning.recommend_session_player", "logic_tracks.create_drummer"],
            unsupportedActions: [
                "convert_session_player_region_to_midi",
                "direct_drummer_performance_parameter_write",
                "force_session_player_style",
                "session_player_direct_performance_control",
            ],
            provenance: documented([sessionOverview]),
            notes: [
                "Apple documents Drummer as a Session Player category.",
                "This MCP build can create a Drummer track, but cannot directly edit Drummer performance controls or convert regions to MIDI.",
            ]
        ),
        sessionPlayer(
            "bass_player",
            "Bass Player",
            kind: .sessionPlayer,
            trackType: .sessionPlayer,
            roles: ["bass", "groove", "accompaniment"],
            genres: ["pop", "rock", "funk", "electronic"],
            relatedStockPluginIDs: ["logic.stock.instrument.studio_bass", "logic.stock.instrument.alchemy"],
            supportedActions: ["planning.recommend_session_player"],
            unsupportedActions: [
                "direct_chord_track_edit",
                "force_session_player_style",
                "session_player_direct_performance_control",
            ],
            provenance: documented([sessionOverview, synthPlayerIntro]),
            notes: [
                "Apple documents Bass Player as a Session Player that can follow the Chord Track or region chords.",
                "Synth Bass styles are documented as Synth Player styles; this catalog keeps them read-only planning metadata.",
            ]
        ),
        sessionPlayer(
            "keyboard_player",
            "Keyboard Player",
            kind: .sessionPlayer,
            trackType: .sessionPlayer,
            roles: ["keys", "piano", "chords", "pad"],
            genres: ["pop", "songwriter", "ambient", "electronic"],
            relatedStockPluginIDs: ["logic.stock.instrument.vintage_electric_piano", "logic.stock.instrument.vintage_b3", "logic.stock.instrument.alchemy"],
            supportedActions: ["planning.recommend_session_player"],
            unsupportedActions: [
                "direct_chord_track_edit",
                "force_session_player_style",
                "session_player_direct_performance_control",
            ],
            provenance: documented([sessionOverview, synthPlayerIntro]),
            notes: [
                "Apple documents Keyboard Player as a Session Player that can follow the Chord Track or region chords.",
                "Synth Keyboard styles may use Alchemy, but this MCP build does not directly instantiate those styles.",
            ]
        ),
        sessionPlayer(
            "synth_player",
            "Synth Player",
            kind: .sessionPlayer,
            trackType: .sessionPlayer,
            roles: ["synth", "bass", "pad", "rhythmic chords"],
            genres: ["electronic", "ambient", "dance", "pop"],
            relatedStockPluginIDs: ["logic.stock.instrument.alchemy", "logic.stock.instrument.retro_synth", "logic.stock.instrument.studio_bass"],
            supportedActions: ["planning.recommend_session_player"],
            unsupportedActions: [
                "direct_chord_track_edit",
                "force_session_player_style",
                "session_player_direct_performance_control",
            ],
            provenance: documented([synthPlayerIntro, logic12WhatsNew]),
            notes: [
                "Apple documents Synth Player styles for Bass Player and Keyboard Player in Logic Pro 12.",
                "This entry is a planning category, not a separate MCP-controllable track creation command.",
            ]
        ),
    ]
}

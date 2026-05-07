import Foundation

/// Transport state from Logic Pro.
struct TransportState: Sendable, Codable {
    var isPlaying: Bool = false
    var isRecording: Bool = false
    var isPaused: Bool = false
    var isCycleEnabled: Bool = false
    var isMetronomeEnabled: Bool = false
    var tempo: Double = 120.0
    var position: String = "1.1.1.1"  // Bar.Beat.Division.Tick
    var timePosition: String = "00:00:00.000"
    var sampleRate: Int = 44100
    var lastUpdated: Date = .distantPast
}

/// Track types in Logic Pro.
enum TrackType: String, Sendable, Codable {
    case audio
    case softwareInstrument = "software_instrument"
    case drummer
    case externalMIDI = "external_midi"
    case aux
    case bus
    case master
    case unknown
}

/// A single track's state.
struct TrackState: Sendable, Codable, Identifiable {
    let id: Int          // 0-based index
    var name: String
    var type: TrackType
    var isMuted: Bool = false
    var isSoloed: Bool = false
    var isArmed: Bool = false
    var isSelected: Bool = false
    var volume: Double = 0.0   // dB, 0 = unity
    var pan: Double = 0.0      // -1.0 (L) to 1.0 (R)
    var automationMode: AutomationMode = .off
    var color: String?
    /// v3.1.8 (Issue #7) — true when this row was synthesised from
    /// MetaData.plist's `NumberOfTracks` because the AX walker returned
    /// empty. Names are placeholders ("Track 1", "Track 2", ...). Live
    /// rows from the AX scrape have this nil/absent (Codable backward
    /// compat: pre-v3.1.8 JSON snapshots lacking the field decode cleanly).
    var placeholder: Bool?
}

/// Mixer channel strip state (extends track with routing info).
struct ChannelStripState: Sendable, Codable {
    var trackIndex: Int
    var volume: Double = 0.0
    var pan: Double = 0.0
    var sends: [SendState] = []
    var input: String?
    var output: String?
    var eqEnabled: Bool = false
    var plugins: [PluginSlotState] = []
}

/// A send on a channel strip.
struct SendState: Sendable, Codable {
    var index: Int
    var destination: String
    var level: Double
    var isPreFader: Bool
}

/// A plugin slot.
struct PluginSlotState: Sendable, Codable {
    var index: Int
    var name: String
    var isBypassed: Bool
}

/// Region info.
struct RegionState: Sendable, Codable, Identifiable {
    let id: String
    var name: String
    var trackIndex: Int
    var startPosition: String   // Bar.Beat
    var endPosition: String
    var length: String
    var isSelected: Bool = false
    var isLooped: Bool = false
}

/// Marker `position`의 출처.
/// - `.parser` — `parseMarkerListPosition` 성공 (canonical "bar.beat.div.tick").
/// - `.fallback` — parser 실패 → caller가 `\(index+1).1.1.1` 합성 (manufactured).
/// - `.unknown` — v3.1.x 이하 cache snapshot decode 결과 (provenance 정보 없음).
///   신규 marker는 항상 `.parser` 또는 `.fallback` 명시; `.unknown` 은 legacy 한정.
enum PositionSource: String, Sendable, Codable, Equatable {
    case parser
    case fallback
    case unknown

    /// canonical 여부 — wire schema의 `is_canonical` derived 필드와
    /// `goto_marker` uncertainty 분기 양쪽에서 단일 진실 소스로 사용한다.
    var isCanonical: Bool { self == .parser }
}

/// Marker 정보.
struct MarkerState: Sendable, Codable, Identifiable, Equatable {
    let id: Int
    var name: String
    var position: String
    var positionSource: PositionSource

    /// `positionSource` 기본값은 `.unknown` — 호출 site가 명시적으로 `.parser`/
    /// `.fallback` 을 지정하지 않으면 silent false provenance 발생을 방지한다
    /// (boomer Phase G P2-1).
    init(id: Int, name: String, position: String, positionSource: PositionSource = .unknown) {
        self.id = id
        self.name = name
        self.position = position
        self.positionSource = positionSource
    }

    // v3.2 — Codable backward compat. v3.1.x snapshot 에 positionSource field 없음 →
    // `.unknown` 으로 decode (false provenance 차단; boomer Phase C P1-2).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(Int.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.position = try c.decode(String.self, forKey: .position)
        self.positionSource = try c.decodeIfPresent(PositionSource.self, forKey: .positionSource)
            ?? .unknown
    }

    /// AX walker 의 두 fallback site 공통 factory — `parsed != nil` → `.parser`,
    /// `nil` → `.fallback` + `\(index+1).1.1.1` 합성. 추가 site에서 정책이 갈라
    /// 지지 않도록 단일화.
    static func fromParsed(_ parsed: String?, id: Int, name: String) -> MarkerState {
        MarkerState(
            id: id,
            name: name,
            position: parsed ?? "\(id + 1).1.1.1",
            positionSource: parsed != nil ? .parser : .fallback
        )
    }
}

/// Automation mode.
enum AutomationMode: String, Sendable, Codable {
    case off
    case read
    case trim
    case touch
    case latch
    case write
}

/// MCU connection state.
struct MCUConnectionState: Sendable {
    var isConnected: Bool = false
    var registeredAsDevice: Bool = false
    var lastFeedbackAt: Date? = nil
    var portName: String = ""
}

/// MCU LCD display state.
struct MCUDisplayState: Sendable {
    var upperRow: String = String(repeating: " ", count: 56)  // 56 chars
    var lowerRow: String = String(repeating: " ", count: 56)
}

/// Project-level info.
struct ProjectInfo: Sendable, Codable {
    var name: String = ""
    var sampleRate: Int = 44100
    var bitDepth: Int = 24
    var tempo: Double = 120.0
    var timeSignature: String = "4/4"
    var trackCount: Int = 0
    var filePath: String?
    var lastUpdated: Date = .distantPast
    /// v3.1.8 (Issue #7) — provenance of the read. One of: "ax_live",
    /// "project_file", "cache", "default". Optional for forward/back compat
    /// (v3.1.7 envelopes deserialise with `source: nil`).
    var source: String?
    /// v3.1.8 (Issue #7) — set when sourced from project_file; mtime delta
    /// in seconds. Clamped to ≥ 0.
    var lastSavedAgeSec: Double?
}

/// A Logic arrange-area region (MIDI or audio) as exposed by AX.
///
/// `startBar` and `endBar` are 1-based bar numbers parsed from Logic's
/// AXHelp text ("리전은 N 마디 에서 시작하여 M 마디 에서 끝납니다." / English
/// equivalent). `trackIndex` is the 0-based track lane matched by the
/// region's vertical position to each track header's Y coordinate.
struct RegionInfo: Sendable, Codable {
    var name: String
    var trackIndex: Int
    var startBar: Int
    var endBar: Int
    var kind: String  // "midi" | "audio" | "unknown"
    var rawHelp: String?  // raw AXHelp text — preserved for debugging parser misses
}

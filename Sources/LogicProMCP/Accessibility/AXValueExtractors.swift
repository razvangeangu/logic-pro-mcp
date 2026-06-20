import ApplicationServices
import Foundation

/// Extract typed values from AX elements.
/// These handle the various ways Logic Pro represents values in its AX tree.
enum AXValueExtractors {
    /// Extract a numeric value from a slider (volume fader, pan knob, etc.)
    /// Returns the AXValue as a Double, or nil if unavailable.
    static func extractSliderValue(_ element: AXUIElement, runtime: AXHelpers.Runtime = .production) -> Double? {
        guard let value = AXHelpers.getValue(element, runtime: runtime) else { return nil }
        // AXSlider values can come as NSNumber or CFNumber
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        // Try string-based value and parse
        if let str = value as? String, let parsed = Double(str) {
            return parsed
        }
        return nil
    }

    /// Read an AX slider's `AXValueDescription` — the human-readable, unit-bearing
    /// rendering of its value (e.g. Logic plugin-window Threshold reads "60 %").
    /// Returns nil when the attribute is absent. Verified-plugin readback (R6
    /// step 12) surfaces this verbatim as `observed_display`.
    static func extractValueDescription(_ element: AXUIElement, runtime: AXHelpers.Runtime = .production) -> String? {
        AXHelpers.getAttribute(element, kAXValueDescriptionAttribute, runtime: runtime)
    }

    /// Set an AX slider's `AXValue` to `value`. Logic plugin-window parameter
    /// sliders accept a numeric `AXValue` write (T0 spike: `set AXValue 60`
    /// lands and reads back). Returns true on a successful AX write. The value is
    /// bridged to `NSNumber` so it crosses the `CFTypeRef` boundary the same way
    /// the live AX API expects.
    @discardableResult
    static func setSliderValue(
        _ element: AXUIElement,
        _ value: Double,
        runtime: AXHelpers.Runtime = .production
    ) -> Bool {
        AXHelpers.setAttribute(element, kAXValueAttribute, NSNumber(value: value), runtime: runtime)
    }

    /// Set a normalized 0.0...1.0 slider value by converting it into the
    /// element's live AX range when one is exposed.
    @discardableResult
    static func setNormalizedSliderValue(
        _ element: AXUIElement,
        _ normalized: Double,
        runtime: AXHelpers.Runtime = .production
    ) -> Bool {
        let clamped = min(max(normalized, 0.0), 1.0)
        guard let range = extractSliderRange(element, runtime: runtime),
              range.max > range.min else {
            return setSliderValue(element, clamped, runtime: runtime)
        }
        let raw = range.min + clamped * (range.max - range.min)
        return setSliderValue(element, raw, runtime: runtime)
    }

    /// Extract a text value from a static text or text field element.
    /// Used for tempo display, position readout, track names, etc.
    static func extractTextValue(_ element: AXUIElement, runtime: AXHelpers.Runtime = .production) -> String? {
        // Try kAXValueAttribute first (text fields, static text)
        if let value = AXHelpers.getValue(element, runtime: runtime) as? String {
            return value
        }
        // Fallback to kAXTitleAttribute
        return AXHelpers.getTitle(element, runtime: runtime)
    }

    /// Extract a boolean state from a button or checkbox element.
    /// For toggle buttons (mute, solo, arm, cycle, metronome), the value
    /// indicates pressed/active state.
    static func extractButtonState(_ element: AXUIElement, runtime: AXHelpers.Runtime = .production) -> Bool? {
        guard let value = AXHelpers.getValue(element, runtime: runtime) else { return nil }
        // Toggle buttons typically report 0/1 as NSNumber
        if let number = value as? NSNumber {
            return number.boolValue
        }
        if let bool = value as? Bool {
            return bool
        }
        // Some buttons use string "1"/"0"
        if let str = value as? String {
            return str == "1" || str.lowercased() == "true"
        }
        return nil
    }

    /// Extract the selected state of an element.
    static func extractSelectedState(_ element: AXUIElement, runtime: AXHelpers.Runtime = .production) -> Bool? {
        guard let value: AnyObject = AXHelpers.getAttribute(element, kAXSelectedAttribute, runtime: runtime) else {
            return nil
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        return nil
    }

    /// Extract slider range (min/max) for interpreting fader values.
    struct SliderRange {
        let min: Double
        let max: Double
    }

    static func extractSliderRange(_ element: AXUIElement, runtime: AXHelpers.Runtime = .production) -> SliderRange? {
        guard let minVal: AnyObject = AXHelpers.getAttribute(element, kAXMinValueAttribute, runtime: runtime),
              let maxVal: AnyObject = AXHelpers.getAttribute(element, kAXMaxValueAttribute, runtime: runtime),
              let min = (minVal as? NSNumber)?.doubleValue,
              let max = (maxVal as? NSNumber)?.doubleValue else {
            return nil
        }
        return SliderRange(min: min, max: max)
    }

    /// Normalize a unipolar Logic AX slider to 0.0...1.0 using its live
    /// AXMin/AXMax range. Logic Pro 12.2 exposes mixer faders as raw values
    /// like 70 in a 0...233 range, while the public MCP mixer contract uses
    /// normalized 0...1 values.
    static func extractNormalizedSliderValue(
        _ element: AXUIElement,
        runtime: AXHelpers.Runtime = .production
    ) -> Double? {
        guard let value = extractSliderValue(element, runtime: runtime),
              let range = extractSliderRange(element, runtime: runtime),
              range.max > range.min else {
            return extractSliderValue(element, runtime: runtime)
        }
        let normalized = (value - range.min) / (range.max - range.min)
        return min(max(normalized, 0.0), 1.0)
    }

    /// Convert Logic's AX fader-position value into the public mixer volume
    /// contract used by `mixer.set_volume`. Logic's AX slider range is not a
    /// linear mirror of the MCU 14-bit fader position; live Logic 12.2 reads
    /// show a stable fader taper (e.g. MCP 0.4 reads as AX 70/233). Interpolate
    /// the observed taper so AX readback and `logic://mixer` speak the same
    /// units as mixer writes.
    static func extractLogicMixerFaderValue(
        _ element: AXUIElement,
        runtime: AXHelpers.Runtime = .production
    ) -> Double? {
        guard let value = extractSliderValue(element, runtime: runtime) else {
            return nil
        }
        guard let range = extractSliderRange(element, runtime: runtime),
              range.max > range.min else {
            return value
        }
        let position = min(max((value - range.min) / (range.max - range.min), 0.0), 1.0)
        guard isLogicMixerRawFaderRange(range) else {
            return position
        }
        return logicMixerFaderPositionToContract(position)
    }

    private static func isLogicMixerRawFaderRange(_ range: SliderRange) -> Bool {
        range.min == 0.0 && range.max > 2.0
    }

    /// Convert the public `mixer.set_volume` contract value back into the live
    /// Logic 12 raw fader position so AX writes land at the intended level.
    static func logicMixerFaderContractToPosition(_ contract: Double) -> Double {
        let clamped = min(max(contract, 0.0), 1.0)
        let points: [(contract: Double, position: Double)] = [
            (0.0, 0.0),
            (0.2, 0.1072961373390558),
            (0.4, 70.0 / 233.0),
            (0.5, 0.4206008583690987),
            (0.6, 0.48497854077253216),
            (0.8, 0.8111587982832618),
            (1.0, 1.0),
        ]
        for index in 1..<points.count {
            let lower = points[index - 1]
            let upper = points[index]
            guard clamped <= upper.contract else { continue }
            let span = upper.contract - lower.contract
            guard span > 0 else { return upper.position }
            let ratio = (clamped - lower.contract) / span
            return lower.position + ratio * (upper.position - lower.position)
        }
        return 1.0
    }

    static func logicMixerFaderPositionToContract(_ position: Double) -> Double {
        let clamped = min(max(position, 0.0), 1.0)
        let points: [(position: Double, contract: Double)] = [
            (0.0, 0.0),
            (0.1072961373390558, 0.2),
            (70.0 / 233.0, 0.4),
            (0.4206008583690987, 0.5),
            (0.48497854077253216, 0.6),
            (0.8111587982832618, 0.8),
            (1.0, 1.0),
        ]
        for index in 1..<points.count {
            let lower = points[index - 1]
            let upper = points[index]
            guard clamped <= upper.position else { continue }
            let span = upper.position - lower.position
            guard span > 0 else { return upper.contract }
            let ratio = (clamped - lower.position) / span
            return lower.contract + ratio * (upper.contract - lower.contract)
        }
        return 1.0
    }

    /// Set a Logic mixer fader using the public 0.0...1.0 contract value. When
    /// Logic exposes the raw 0...233 AX range, interpolate through the observed
    /// taper first so write and readback use the same contract space.
    @discardableResult
    static func setLogicMixerFaderValue(
        _ element: AXUIElement,
        _ value: Double,
        runtime: AXHelpers.Runtime = .production
    ) -> Bool {
        let clamped = min(max(value, 0.0), 1.0)
        guard let range = extractSliderRange(element, runtime: runtime),
              range.max > range.min else {
            return setSliderValue(element, clamped, runtime: runtime)
        }
        let position = isLogicMixerRawFaderRange(range)
            ? logicMixerFaderContractToPosition(clamped)
            : clamped
        let raw = range.min + position * (range.max - range.min)
        return setSliderValue(element, raw, runtime: runtime)
    }

    /// Normalize a bipolar Logic AX slider to -1.0...1.0. Pan knobs in Logic
    /// 12.2 expose asymmetric integer ranges (-64...63); treating zero as
    /// the electrical center avoids surfacing a small false right-pan offset.
    static func extractCenteredSliderValue(
        _ element: AXUIElement,
        runtime: AXHelpers.Runtime = .production
    ) -> Double? {
        guard let value = extractSliderValue(element, runtime: runtime),
              let range = extractSliderRange(element, runtime: runtime),
              range.min < 0.0,
              range.max > 0.0 else {
            return extractNormalizedSliderValue(element, runtime: runtime)
        }
        if value == 0.0 { return 0.0 }
        if value < 0.0 {
            return max(value / abs(range.min), -1.0)
        }
        return min(value / range.max, 1.0)
    }

    /// Set a centered slider using the public -1.0...1.0 contract. Logic 12.2
    /// pan knobs expose an asymmetric integer AX range (-64...63), so map the
    /// negative and positive sides independently to preserve true center.
    @discardableResult
    static func setCenteredSliderValue(
        _ element: AXUIElement,
        _ value: Double,
        runtime: AXHelpers.Runtime = .production
    ) -> Bool {
        let clamped = min(max(value, -1.0), 1.0)
        guard let range = extractSliderRange(element, runtime: runtime),
              range.min < 0.0,
              range.max > 0.0 else {
            return setSliderValue(element, clamped, runtime: runtime)
        }
        let raw: Double
        if clamped < 0.0 {
            raw = clamped * abs(range.min)
        } else if clamped > 0.0 {
            raw = clamped * range.max
        } else {
            raw = 0.0
        }
        return setSliderValue(element, raw, runtime: runtime)
    }

    /// Read a track header and extract its basic state.
    static func extractTrackState(
        from header: AXUIElement,
        index: Int,
        runtime: AXHelpers.Runtime = .production
    ) -> TrackState {
        let name = extractTrackName(from: header, runtime: runtime)
        let muted = extractTrackButtonState(from: header, prefix: "Mute", runtime: runtime) ?? false
        let soloed = extractTrackButtonState(from: header, prefix: "Solo", runtime: runtime) ?? false
        let armed = extractTrackButtonState(from: header, prefix: "Record", runtime: runtime) ?? false
        let selected = extractSelectedState(header, runtime: runtime) ?? false
        let trackType = inferTrackType(from: header, runtime: runtime)

        return TrackState(
            id: index,
            name: name,
            type: trackType,
            isMuted: muted,
            isSoloed: soloed,
            isArmed: armed,
            isSelected: selected,
            volume: 0.0,
            pan: 0.0,
            color: extractTrackColor(from: header, runtime: runtime)
        )
    }

    /// Read transport bar elements and build a TransportState.
    static func extractTransportState(
        from transport: AXUIElement,
        runtime: AXHelpers.Runtime = .production
    ) -> TransportState {
        var state = TransportState()

        // Find and read transport button / checkbox states.
        let controls = AXHelpers.findAllDescendants(of: transport, role: kAXButtonRole, maxDepth: 4, runtime: runtime)
            + AXHelpers.findAllDescendants(of: transport, role: kAXCheckBoxRole, maxDepth: 4, runtime: runtime)
        for control in controls {
            let desc = [
                AXHelpers.getDescription(control, runtime: runtime),
                AXHelpers.getTitle(control, runtime: runtime),
            ].compactMap { $0 }.joined(separator: " ")
            let pressed = extractButtonState(control, runtime: runtime) ?? false
            let descLower = desc.lowercased()

            if descLower.contains("play") || descLower.contains("재생") {
                state.isPlaying = pressed
            } else if (descLower.contains("record") || descLower.contains("녹음")) && !descLower.contains("arm") && !descLower.contains("활성화") {
                state.isRecording = pressed
            } else if descLower.contains("cycle") || descLower.contains("loop") || descLower.contains("사이클") {
                state.isCycleEnabled = pressed
            } else if descLower.contains("metronome") || descLower.contains("click") || descLower.contains("메트로놈") || descLower.contains("클릭") {
                state.isMetronomeEnabled = pressed
            }
        }

        // Find text fields / sliders for tempo and position.
        let texts = AXHelpers.findAllDescendants(of: transport, role: kAXStaticTextRole, maxDepth: 4, runtime: runtime)
            + AXHelpers.findAllDescendants(of: transport, role: kAXTextFieldRole, maxDepth: 4, runtime: runtime)
        for text in texts {
            guard let value = extractTextValue(text, runtime: runtime) else { continue }
            let desc = AXHelpers.getDescription(text, runtime: runtime) ?? ""
            let descLower = desc.lowercased()

            if descLower.contains("tempo") || descLower.contains("bpm") || descLower.contains("템포") {
                if let tempo = Double(value.replacingOccurrences(of: " BPM", with: "")) {
                    state.tempo = tempo
                }
            } else if descLower.contains("position") || descLower.contains("재생헤드 위치") || value.contains(".") && value.contains(":") == false {
                // Bar.Beat.Division.Tick format
                if value.filter({ $0 == "." }).count >= 2 {
                    state.position = value
                }
            } else if value.contains(":") {
                // Time format HH:MM:SS
                state.timePosition = value
            }
        }

        let sliders = AXHelpers.findAllDescendants(of: transport, role: kAXSliderRole, maxDepth: 4, runtime: runtime)
        var barValue: Int?
        var beatValue: Int?
        for slider in sliders {
            let desc = (AXHelpers.getDescription(slider, runtime: runtime) ?? "").lowercased()
            if (desc.contains("tempo") || desc.contains("템포")), let tempo = extractSliderValue(slider, runtime: runtime) {
                state.tempo = tempo
            } else if desc.contains("마디") || desc.contains("bar") {
                barValue = Int(extractSliderValue(slider, runtime: runtime) ?? 0)
            } else if desc.contains("비트") || desc.contains("beat") {
                beatValue = Int(extractSliderValue(slider, runtime: runtime) ?? 0)
            }
        }
        if let barValue, let beatValue {
            state.position = "\(barValue).\(beatValue).1.1"
        }

        state.lastUpdated = Date()
        return state
    }

    // MARK: - Private helpers

    private static func extractTrackName(from header: AXUIElement, runtime: AXHelpers.Runtime) -> String {
        // Logic 12.2 commonly exposes the authoritative live name on an
        // AXTextField's description while AXValue stays the numeric placeholder
        // "0". Prefer text-field metadata when it contains a real name; fall
        // back to static text only when the text-field path is empty/useless.
        let textFields = AXHelpers.findAllDescendants(
            of: header, role: kAXTextFieldRole, maxDepth: 3, runtime: runtime
        )
        for field in textFields {
            let candidates = [
                AXHelpers.getDescription(field, runtime: runtime),
                AXHelpers.getTitle(field, runtime: runtime),
                extractTextValue(field, runtime: runtime)
            ]
            for candidate in candidates.compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) }) {
                if !candidate.isEmpty, candidate != "0" {
                    return candidate
                }
            }
        }

        if let text = AXHelpers.findDescendant(
            of: header, role: kAXStaticTextRole, maxDepth: 3, runtime: runtime
        ),
           let name = extractTextValue(text, runtime: runtime)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }

        // AXLayoutItem headers commonly describe themselves as `4개의 ‘Holographic Squares’ 트랙`.
        if let desc = AXHelpers.getDescription(header, runtime: runtime),
           let quotedName = extractQuotedTrackName(from: desc) {
            return quotedName
        }

        if let title = AXHelpers.getTitle(header, runtime: runtime)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            return title
        }
        return "Untitled"
    }

    private static func extractTrackButtonState(
        from header: AXUIElement,
        prefix: String,
        runtime: AXHelpers.Runtime
    ) -> Bool? {
        let localizedKeywords: [String: [String]] = [
            "Mute": ["Mute", "음소거"],
            "Solo": ["Solo", "솔로"],
            "Record": ["Record", "Rec", "녹음 활성화", "레코드 활성화"]
        ]
        let keywords = localizedKeywords[prefix] ?? [prefix]
        let controls = AXHelpers.findAllDescendants(of: header, role: kAXButtonRole, maxDepth: 4, runtime: runtime)
            + AXHelpers.findAllDescendants(of: header, role: kAXCheckBoxRole, maxDepth: 4, runtime: runtime)
        for control in controls {
            let desc = (
                AXHelpers.getDescription(control, runtime: runtime)
                    ?? AXHelpers.getTitle(control, runtime: runtime)
                    ?? ""
            ).lowercased()
            if keywords.contains(where: { desc.contains($0.lowercased()) }) {
                return extractButtonState(control, runtime: runtime)
            }
        }
        return nil
    }

    private static func inferTrackType(from header: AXUIElement, runtime: AXHelpers.Runtime) -> TrackType {
        // Logic 12.2 often puts the human track name on the AXLayoutItem and
        // the type hint on a descendant icon/control, so scan both levels.
        var signals = [
            AXHelpers.getDescription(header, runtime: runtime),
            AXHelpers.getTitle(header, runtime: runtime),
            AXHelpers.getIdentifier(header, runtime: runtime),
            AXHelpers.getHelp(header, runtime: runtime),
            extractTrackName(from: header, runtime: runtime)
        ]
        let descendants = AXHelpers.findAllDescendants(of: header, maxDepth: 4, runtime: runtime)
        for element in descendants {
            signals.append(contentsOf: [
                AXHelpers.getDescription(element, runtime: runtime),
                AXHelpers.getTitle(element, runtime: runtime),
                AXHelpers.getIdentifier(element, runtime: runtime),
                AXHelpers.getHelp(element, runtime: runtime),
                extractTextValue(element, runtime: runtime)
            ])
        }
        let combined = signals
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        if combined.contains("audio") || combined.contains("오디오") { return .audio }
        if combined.contains("instrument") || combined.contains("software") || combined.contains("악기") { return .softwareInstrument }
        if combined.contains("drummer") { return .drummer }
        if combined.contains("external") || combined.contains("midi") { return .externalMIDI }
        if combined.contains("aux") { return .aux }
        if combined.contains("bus") { return .bus }
        if combined.contains("master") || combined.contains("stereo out") { return .master }
        return .unknown
    }

    private static func extractQuotedTrackName(from description: String) -> String? {
        let patterns = ["‘([^’]+)’", "'([^']+)'", "\"([^\"]+)\""]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: description, range: NSRange(description.startIndex..., in: description)),
               let range = Range(match.range(at: 1), in: description) {
                let candidate = description[range].trimmingCharacters(in: .whitespacesAndNewlines)
                if !candidate.isEmpty {
                    return candidate
                }
            }
        }
        return nil
    }

    private static func extractTrackColor(from header: AXUIElement, runtime: AXHelpers.Runtime) -> String? {
        // Logic Pro may expose color via a custom attribute or the element's description
        let desc = AXHelpers.getDescription(header, runtime: runtime) ?? ""
        if desc.lowercased().contains("color") {
            return desc
        }
        return nil
    }
}

import Foundation

/// Shared parser for the `"pitch,offsetMs,durMs[,vel[,ch]];..."` note-sequence
/// format used by `midi.play_sequence` and `record_sequence`.
///
/// **v3.1.x — strict whole-parse-fail contract (T3).**
/// Returns `Result<[ParsedNote], NoteSequenceParseError>` instead of silently
/// dropping invalid segments. A single malformed segment fails the entire
/// parse so callers can surface a precise diagnostic to the LLM agent
/// (rather than leaving the agent to guess why N-1 notes survived). Empty
/// input still yields `.success([])` because zero is a valid count — only
/// *malformed* input is an error.
///
/// **Channel field is 1-based (input 1..16 → wire byte 0..15).** This matches
/// Logic Pro's UI numbering and `send_note`/`send_cc`. ch=0 and ch≥17 are
/// rejected; an omitted channel defaults to Ch 1 (wire byte 0).
///
/// Callers layer their own upper bounds on top of the result (256 for
/// real-time `play_sequence`, 1024 for SMF import in `record_sequence`).
enum NoteSequenceParser {
    struct ParsedNote: Equatable {
        let pitch: UInt8       // 0...127
        let offsetMs: Int      // >= 0
        let durationMs: Int    // 1...30000
        let velocity: UInt8    // 0...127
        let channel: UInt8     // 0...15 (wire byte; user-facing was 1..16)
    }

    /// Why a parse failed. Each case carries the offending segment text so
    /// the caller can include it in the user-visible error message.
    enum NoteSequenceParseError: Error, Equatable {
        /// Channel field present but outside 1..16 (1-based input range).
        /// `value` is the rejected raw integer; `segment` is the full segment.
        case channelOutOfRange(segment: String, value: Int)
        /// Pitch field missing or outside 0..127.
        case invalidPitch(segment: String)
        /// Offset (<0) or duration (outside 1..30000).
        case invalidTiming(segment: String)
        /// Insufficient fields, non-numeric values, or velocity outside 0..127.
        case malformed(segment: String)

        /// One-line human-readable hint suitable for embedding in a State C
        /// envelope. Tests grep for the lower-case words "channel" / "pitch"
        /// / "timing" / "malformed" — keep wording stable.
        var hint: String {
            switch self {
            case .channelOutOfRange(let segment, let value):
                return "channel \(value) out of range (must be 1..16) in segment '\(segment)'"
            case .invalidPitch(let segment):
                return "invalid pitch (must be 0..127) in segment '\(segment)'"
            case .invalidTiming(let segment):
                return "invalid timing (offset>=0, duration 1..30000) in segment '\(segment)'"
            case .malformed(let segment):
                return "malformed segment '\(segment)' (expected 'pitch,offsetMs,durMs[,vel[,ch]]')"
            }
        }
    }

    static func parse(_ notes: String) -> Result<[ParsedNote], NoteSequenceParseError> {
        // Empty input is a legitimate "no notes" signal, not an error.
        // Splitting "" on ";" yields [], so the loop below would also produce
        // .success([]) — this short-circuit is just for clarity.
        guard !notes.isEmpty else { return .success([]) }

        var parsed: [ParsedNote] = []
        for raw in notes.split(separator: ";") {
            let segment = String(raw)
            // Skip whitespace-only segments (e.g. trailing ";"). split(omittingEmptySubsequences:)
            // already strips empty tokens; this guards against "  " only.
            if segment.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            switch parseSegment(segment) {
            case .success(let note):
                parsed.append(note)
            case .failure(let error):
                return .failure(error)
            }
        }
        return .success(parsed)
    }

    private static func parseSegment(_ segment: String) -> Result<ParsedNote, NoteSequenceParseError> {
        let parts = segment.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        // Need at least pitch, offset, duration.
        guard parts.count >= 3 else {
            return .failure(.malformed(segment: segment))
        }

        guard let pitch = Int(parts[0]) else {
            return .failure(.malformed(segment: segment))
        }
        guard (0...127).contains(pitch) else {
            return .failure(.invalidPitch(segment: segment))
        }

        guard let offset = Int(parts[1]) else {
            return .failure(.malformed(segment: segment))
        }
        guard offset >= 0 else {
            return .failure(.invalidTiming(segment: segment))
        }

        guard let duration = Int(parts[2]) else {
            return .failure(.malformed(segment: segment))
        }
        guard (1...30_000).contains(duration) else {
            return .failure(.invalidTiming(segment: segment))
        }

        // Velocity is optional; default 100. If present it must be a number
        // in 0..127 — out-of-range velocities used to be silently clamped to
        // the default, which masked typos. Strict-fail is the new contract.
        let velocity: Int
        if parts.count >= 4 {
            guard let v = Int(parts[3]), (0...127).contains(v) else {
                return .failure(.malformed(segment: segment))
            }
            velocity = v
        } else {
            velocity = 100
        }

        // Channel is optional; default Ch 1 (wire byte 0). Input is 1..16,
        // wire byte is 0..15. Out-of-range fails the whole parse so the
        // caller can complain explicitly rather than have the user wonder
        // why their ch=17 silently became ch=1.
        let channelWire: UInt8
        if parts.count >= 5 {
            guard let chRaw = Int(parts[4]) else {
                return .failure(.malformed(segment: segment))
            }
            guard (1...16).contains(chRaw) else {
                return .failure(.channelOutOfRange(segment: segment, value: chRaw))
            }
            channelWire = UInt8(chRaw - 1)
        } else {
            channelWire = 0
        }

        return .success(ParsedNote(
            pitch: UInt8(pitch),
            offsetMs: offset,
            durationMs: duration,
            velocity: UInt8(velocity),
            channel: channelWire
        ))
    }
}

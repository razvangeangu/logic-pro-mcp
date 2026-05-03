import Foundation

/// v3.1.1 (P2-2) — lightweight detector that tells whether a `ChannelResult`
/// success message is already a Honest Contract envelope. The channel
/// wrappers that came online with v3.1.1 (AppleScript / CGEvent / MIDI Key
/// Commands) call this before re-wrapping so a future refactor that produces
/// an envelope directly inside the script body does not get double-wrapped.
///
/// Detection is structural (parse JSON, check for the contract's mandatory
/// keys) rather than substring-based to avoid false positives from
/// AppleScript outputs that happen to contain the word `success` in free
/// text. Lives outside `HonestContract.swift` because that file is owned by
/// the v3.1.1 P0 stream and we want to keep the P1/P2 patches mergeable
/// without a touchpoint there.
enum HonestContractEnvelopeDetector {
    /// True when `message` deserializes to a JSON object that carries the
    /// HC contract keys:
    ///   - State A: `{"success":true,"verified":true,...}`
    ///   - State B: `{"success":true,"verified":false,"reason":"...",...}`
    ///   - State C: `{"success":false,"error":"...",...}`
    /// Free-form text and JSON missing those keys return false.
    static func isAlreadyEnvelope(_ message: String) -> Bool {
        guard let data = message.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data),
              let obj = raw as? [String: Any],
              let success = obj["success"] as? Bool else {
            return false
        }
        if success {
            // State A or B — both carry `verified`.
            return obj["verified"] != nil
        }
        // State C — must carry `error`.
        return obj["error"] is String
    }
}

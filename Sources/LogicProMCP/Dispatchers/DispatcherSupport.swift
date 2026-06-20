import Foundation
import MCP

func intParam(_ params: [String: Value], _ keys: String..., default defaultValue: Int = 0) -> Int {
    for key in keys {
        if let value = params[key]?.intValue {
            return value
        }
        // Accept string-form integers too (client convenience).
        if let s = params[key]?.stringValue, let value = Int(s) {
            return value
        }
    }
    return defaultValue
}

/// Like `intParam` but returns `nil` when none of the keys are present.
/// Use for required parameters where a silent default is dangerous — e.g.
/// `index` on mutating track commands where falling through to track 0
/// would edit the wrong track on a malformed caller request.
func intParamOrNil(_ params: [String: Value], _ keys: String...) -> Int? {
    var selected: Int?
    for key in keys {
        guard let raw = params[key] else { continue }
        let parsed: Int? = {
            if let value = raw.intValue { return value }
            if let value = raw.doubleValue, value.isFinite { return Int(exactly: value) }
            if let s = raw.stringValue {
                return Int(s.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return nil
        }()
        guard let parsed else {
            return nil
        }
        if let selected {
            guard selected == parsed else { return nil }
        } else {
            selected = parsed
        }
    }
    return selected
}

func doubleParam(_ params: [String: Value], _ keys: String..., default defaultValue: Double = 0) -> Double {
    for key in keys {
        // JSON integers decode as Value.int — Value.doubleValue returns nil for those.
        // Accept int, double, or numeric string so callers can send `{"tempo": 120}` or `120.5` or `"120"`.
        if let value = params[key]?.doubleValue {
            return value
        }
        if let value = params[key]?.intValue {
            return Double(value)
        }
        if let s = params[key]?.stringValue, let value = Double(s) {
            return value
        }
    }
    return defaultValue
}

func doubleParamOrNil(_ params: [String: Value], _ keys: String...) -> Double? {
    var selected: Double?
    for key in keys {
        guard let raw = params[key] else { continue }
        let parsed: Double? = {
            if let value = raw.doubleValue { return value }
            if let value = raw.intValue { return Double(value) }
            if let s = raw.stringValue { return Double(s) }
            return nil
        }()
        guard let parsed, parsed.isFinite else { return nil }
        if let selected {
            guard selected == parsed else { return nil }
        } else {
            selected = parsed
        }
    }
    return selected
}

func stringParam(_ params: [String: Value], _ keys: String..., default defaultValue: String = "") -> String {
    for key in keys {
        if let value = params[key]?.stringValue {
            return value
        }
        // Coerce adjacent primitive shapes — callers may send numeric or boolean
        // values for string-typed params (e.g. `{"name": 42}`) and silently
        // losing them to the default mask bugs in production.
        if let value = params[key]?.intValue {
            return String(value)
        }
        if let value = params[key]?.doubleValue {
            return String(value)
        }
        if let value = params[key]?.boolValue {
            return value ? "true" : "false"
        }
    }
    return defaultValue
}

func boolParam(_ params: [String: Value], _ keys: String..., default defaultValue: Bool = false) -> Bool {
    for key in keys {
        if let value = params[key]?.boolValue {
            return value
        }
        // Accept canonical string ("true"/"false") and 0/1 ints — common client
        // conveniences. Silent default on mistyped input used to bury real bugs.
        if let s = params[key]?.stringValue?.lowercased() {
            if s == "true" || s == "1" || s == "yes" { return true }
            if s == "false" || s == "0" || s == "no" { return false }
        }
        if let value = params[key]?.intValue {
            return value != 0
        }
    }
    return defaultValue
}

func boolParamOrNil(_ params: [String: Value], _ keys: String...) -> Bool? {
    for key in keys {
        guard let raw = params[key] else { continue }
        if let value = raw.boolValue {
            return value
        }
        if let s = raw.stringValue?.lowercased() {
            if s == "true" || s == "1" || s == "yes" { return true }
            if s == "false" || s == "0" || s == "no" { return false }
            return nil
        }
        if let value = raw.intValue {
            guard value == 0 || value == 1 else { return nil }
            return value == 1
        }
        return nil
    }
    return nil
}

enum StrictBoolParam {
    case missing
    case value(Bool)
    case invalid(String)
}

func strictBoolParam(_ params: [String: Value], _ key: String) -> StrictBoolParam {
    guard let raw = params[key] else { return .missing }
    guard let value = raw.boolValue else {
        return .invalid("'\(key)' must be a literal boolean true or false")
    }
    return .value(value)
}

func csvIntListOrStringParam(_ params: [String: Value], key: String) -> String {
    if let array = params[key]?.arrayValue {
        // Coerce each element through int/double/string the same way doubleParam
        // does — silently dropping doubles/strings was a bug in the prior
        // implementation that turned `[60, 64.0, "67"]` into just "60".
        return array.compactMap { v -> Int? in
            if let i = v.intValue { return i }
            if let d = v.doubleValue { return Int(d) }
            if let s = v.stringValue, let i = Int(s) { return i }
            return nil
        }.map(String.init).joined(separator: ",")
    }
    return params[key]?.stringValue ?? ""
}

func routedTextResult(
    _ router: ChannelRouter,
    operation: String,
    params: [String: String] = [:]
) async -> CallTool.Result {
    toolTextResult(await router.route(operation: operation, params: params))
}

private let dispatcherJSONDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}()

func decodedJSONObject(_ raw: String) -> [String: Any]? {
    guard let data = raw.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return nil
    }
    return object
}

func decodeJSONValue<T: Decodable>(_ type: T.Type, from raw: String) -> T? {
    guard let data = raw.data(using: .utf8) else { return nil }
    return try? dispatcherJSONDecoder.decode(type, from: data)
}

func honestContractExtras(from raw: String) -> [String: Any] {
    guard var object = decodedJSONObject(raw) else { return [:] }
    for key in ["success", "verified", "reason", "error", "state", "hc_schema"] {
        object.removeValue(forKey: key)
    }
    return object
}

func channelResultIsVerified(_ result: ChannelResult) -> Bool {
    guard result.isSuccess else { return false }
    return decodedJSONObject(result.message)?["verified"] as? Bool == true
}

func channelResultIsUnverified(_ result: ChannelResult) -> Bool {
    guard result.isSuccess else { return false }
    return decodedJSONObject(result.message)?["verified"] as? Bool == false
}

func toolTextResultTreatingUnverifiedAsError(_ result: ChannelResult) -> CallTool.Result {
    if channelResultIsUnverified(result) {
        return toolTextResult(result.message, isError: true)
    }
    return toolTextResult(result)
}

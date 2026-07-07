import Foundation

extension SetupDoctor {
    static func normalizeVersion(_ raw: String) -> String {
        Self.SemanticVersion(raw)?.normalizedCore ?? raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^[vV]"#, with: "", options: .regularExpression)
            .components(separatedBy: "-").first ?? raw
    }

    static func compareVersions(_ a: String, _ b: String) -> Int {
        guard let lhs = Self.SemanticVersion(a), let rhs = Self.SemanticVersion(b) else {
            return legacyCompareVersions(a, b)
        }
        if lhs == rhs { return 0 }
        return lhs < rhs ? -1 : 1
    }

    private static func legacyCompareVersions(_ a: String, _ b: String) -> Int {
        let lhs = a.split(separator: ".").map { Int($0) ?? 0 }
        let rhs = b.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(lhs.count, rhs.count)
        for index in 0..<count {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left < right ? -1 : 1 }
        }
        return 0
    }
}

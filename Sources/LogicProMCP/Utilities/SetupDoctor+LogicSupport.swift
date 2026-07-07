import Foundation

extension SetupDoctor {
    static func staticVersion(fromStringsOutput output: String) -> StaticVersionResult {
        let markerPrefix = "LOGIC_PRO_MCP_VERSION="
        let markerVersions = output
            .split(separator: "\n")
            .compactMap { line -> String? in
                let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard value.hasPrefix(markerPrefix) else { return nil }
                let version = String(value.dropFirst(markerPrefix.count))
                return Self.SemanticVersion(version)?.normalizedCore
            }
        if let marker = markerVersions.first {
            return .version(marker)
        }

        var versions: [String] = []
        for line in output.split(separator: "\n") {
            let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let version = Self.SemanticVersion(value), version.major > 0 else {
                continue
            }
            if !versions.contains(version.normalizedCore) {
                versions.append(version.normalizedCore)
            }
        }
        return versions.count == 1 ? .version(versions[0]) : .indeterminate(versions)
    }


    static func preferredLogicApp(_ apps: [LogicAppInfo]) -> LogicAppInfo? {
        apps.first { $0.path == "/Applications/Logic Pro.app" } ?? apps.first
    }


    static func preferredReadableLogicApp(_ apps: [LogicAppInfo]) -> LogicAppInfo? {
        let readable = apps.filter { $0.readable && $0.version != nil }
        return preferredLogicApp(readable)
    }


    static func productionLogicApps() -> [LogicAppInfo] {
        let homeLogic = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/Logic Pro.app").path
        return ["/Applications/Logic Pro.app", homeLogic].compactMap { path -> LogicAppInfo? in
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { return nil }
            let infoURL = URL(fileURLWithPath: path).appendingPathComponent("Contents/Info.plist")
            guard let data = try? Data(contentsOf: infoURL),
                  let plist = try? PropertyListSerialization.propertyList(
                    from: data,
                    options: [],
                    format: nil
                  ) as? [String: Any] else {
                return LogicAppInfo(path: path, version: nil, bundleID: nil, readable: false)
            }
            return LogicAppInfo(
                path: path,
                version: plist["CFBundleShortVersionString"] as? String,
                bundleID: plist["CFBundleIdentifier"] as? String,
                readable: plist["CFBundleShortVersionString"] as? String != nil
            )
        }
    }


}

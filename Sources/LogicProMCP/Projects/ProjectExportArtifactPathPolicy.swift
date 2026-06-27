import Foundation

enum ProjectExportArtifactPathPolicy {
    private static let supportedArtifactExtensions: Set<String> = [
        "wav", "wave", "aif", "aiff", "aifc", "m4a", "mp3",
    ]

    static func standardizedStemPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.deletingPathExtension().path
    }

    static func helperProducedPathMatchesPlannedStem(producedPath: String, plannedPath: String) -> Bool {
        standardizedStemPath(producedPath) == standardizedStemPath(plannedPath)
    }

    static func preferredExistingVariant(for plannedPath: String, fileManager: FileManager) -> String? {
        let plannedURL = URL(fileURLWithPath: plannedPath).standardizedFileURL
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: plannedURL.path, isDirectory: &isDir), !isDir.boolValue {
            return plannedURL.path
        }

        let parent = plannedURL.deletingLastPathComponent()
        let plannedStem = plannedURL.deletingPathExtension().lastPathComponent.lowercased()
        guard let entries = try? fileManager.contentsOfDirectory(atPath: parent.path) else {
            return nil
        }

        let matches = entries.compactMap { entry -> String? in
            let candidate = parent.appendingPathComponent(entry).standardizedFileURL
            let candidateExtension = candidate.pathExtension.lowercased()
            guard supportedArtifactExtensions.contains(candidateExtension),
                  candidate.deletingPathExtension().lastPathComponent.lowercased() == plannedStem else {
                return nil
            }
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: candidate.path, isDirectory: &isDir), !isDir.boolValue else {
                return nil
            }
            return candidate.path
        }
            .sorted()

        return matches.first
    }
}

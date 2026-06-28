import Foundation

func makeExportPlannerDirectory(_ name: String = UUID().uuidString) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func makeExportPlannerProject(named name: String = "Planner Song") throws -> URL {
    let url = try makeExportPlannerDirectory()
        .appendingPathComponent(name)
        .appendingPathExtension("logicx")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

final class UnreadableAttributesFileManager: FileManager {
    override func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        throw CocoaError(.fileReadUnknown)
    }
}

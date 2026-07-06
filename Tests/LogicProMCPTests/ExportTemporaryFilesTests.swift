import Testing
import Foundation
@testable import LogicProMCP

@Test func testExportTemporaryFilesCreatesPrivateRegisteredFile() throws {
    let base = try temporaryExportTestDirectory()
    defer { try? FileManager.default.removeItem(at: base) }

    let file = try ExportTemporaryFiles.temporaryExportFile(baseDirectory: base)
    defer { ExportTemporaryFiles.cleanupTemporaryExportFile(file) }

    #expect(FileManager.default.fileExists(atPath: file.directoryURL.path))
    #expect(file.fileURL.path.hasPrefix(file.directoryURL.path + "/"))
    #expect(file.fileURL.pathExtension == "mid")
    #expect(ExportTemporaryFiles.isManagedTemporaryExportFile(file.fileURL.path))

    let attributes = try FileManager.default.attributesOfItem(atPath: file.directoryURL.path)
    let permissions = try #require(attributes[FileAttributeKey.posixPermissions] as? NSNumber)
    #expect(permissions.intValue & 0o777 == 0o700)
}

@Test func testExportTemporaryFilesCleanupRemovesDirectoryAndRegistryEntry() throws {
    let base = try temporaryExportTestDirectory()
    defer { try? FileManager.default.removeItem(at: base) }

    let file = try ExportTemporaryFiles.temporaryExportFile(baseDirectory: base)
    try Data([0x4D, 0x54]).write(to: file.fileURL)

    ExportTemporaryFiles.cleanupTemporaryExportFile(file)

    #expect(!FileManager.default.fileExists(atPath: file.directoryURL.path))
    #expect(!ExportTemporaryFiles.isManagedTemporaryExportFile(file.fileURL.path))
}

@Test func testExportTemporaryFilesCleanupDeletesOwnedDirectoriesOnly() throws {
    let base = try temporaryExportTestDirectory()
    defer { try? FileManager.default.removeItem(at: base) }

    let ownedDir = ExportTemporaryFiles.temporaryDirectoryPrefix(baseDirectory: base) + UUID().uuidString
    let unrelatedFile = base.appendingPathComponent("unrelated.mid")
    let symlinkTarget = base.appendingPathComponent("attacker-target", isDirectory: true)
    let symlinkPath = ExportTemporaryFiles.temporaryDirectoryPrefix(baseDirectory: base) + "symlink"

    try FileManager.default.createDirectory(atPath: ownedDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: symlinkTarget, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: "\(ownedDir)/owned.mid", contents: Data([0, 1, 2]))
    FileManager.default.createFile(atPath: unrelatedFile.path, contents: Data([0, 1, 2]))
    try FileManager.default.createSymbolicLink(atPath: symlinkPath, withDestinationPath: symlinkTarget.path)

    let oldDate = Date().addingTimeInterval(-600)
    try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: ownedDir)
    try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: unrelatedFile.path)

    ExportTemporaryFiles.cleanupOrphanFiles(in: base.path, olderThan: 300)

    #expect(!FileManager.default.fileExists(atPath: ownedDir))
    #expect(FileManager.default.fileExists(atPath: unrelatedFile.path))
    #expect(FileManager.default.fileExists(atPath: symlinkTarget.path))
}

@Test func testExportTemporaryFilesOrphanCleanupUnregistersDeletedFiles() throws {
    let base = try temporaryExportTestDirectory()
    defer { try? FileManager.default.removeItem(at: base) }

    let file = try ExportTemporaryFiles.temporaryExportFile(baseDirectory: base)
    try Data([0x4D, 0x54]).write(to: file.fileURL)
    try FileManager.default.setAttributes(
        [.modificationDate: Date().addingTimeInterval(-600)],
        ofItemAtPath: file.directoryURL.path
    )

    #expect(ExportTemporaryFiles.isManagedTemporaryExportFile(file.fileURL.path))

    ExportTemporaryFiles.cleanupOrphanFiles(in: base.path, olderThan: 300)

    #expect(!FileManager.default.fileExists(atPath: file.directoryURL.path))
    #expect(!ExportTemporaryFiles.isManagedTemporaryExportFile(file.fileURL.path))
}

@Test func testExportTemporaryFilesCleanupHandlesMissingDirectory() {
    ExportTemporaryFiles.cleanupOrphanFiles(in: "/tmp/does-not-exist-\(UUID().uuidString)")
}

private func temporaryExportTestDirectory() throws -> URL {
    let path = NSTemporaryDirectory() + "ExportTemporaryFilesTests-\(UUID().uuidString)"
    let url = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

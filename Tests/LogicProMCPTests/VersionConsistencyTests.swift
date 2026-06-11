import Foundation
import Testing
@testable import LogicProMCP

private func repositoryRootURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func readRepoFile(_ relativePath: String) throws -> String {
    try String(
        contentsOf: repositoryRootURL().appendingPathComponent(relativePath),
        encoding: .utf8
    )
}

/// Prevents the kind of drift we cleaned up in the v2.2 census:
/// ServerConfig said 2.2.0 while Formula was 2.1.0 and manifest/install.sh
/// were pinned to v2.0.0. Any future version bump has to touch all four
/// artefacts or this test fails.
@Test func testServerVersionMatchesPackagingArtefacts() throws {
    let sourceVersion = ServerConfig.serverVersion
    #expect(
        sourceVersion == "3.5.0",
        "stock plugin and workflow resources expand the public surface, so this branch must not identify as v3.4.6"
    )

    let manifest = try readRepoFile("manifest.json")
    #expect(
        manifest.contains("\"version\": \"\(sourceVersion)\""),
        "manifest.json version field must match ServerConfig.serverVersion=\(sourceVersion)"
    )
    #expect(
        manifest.contains("releases/download/v\(sourceVersion)/"),
        "manifest.json download_url must pin v\(sourceVersion)"
    )

    let formula = try readRepoFile("Formula/logic-pro-mcp.rb")
    #expect(
        formula.contains("version \"\(sourceVersion)\""),
        "Formula/logic-pro-mcp.rb version must match ServerConfig.serverVersion=\(sourceVersion)"
    )

    let installScript = try readRepoFile("Scripts/install.sh")
    #expect(
        installScript.contains("LOGIC_PRO_MCP_VERSION:-v\(sourceVersion)"),
        "Scripts/install.sh default VERSION must match v\(sourceVersion)"
    )
}

@Test func testManifestResourceSurfaceMatchesRegisteredProvider() throws {
    let manifest = try sharedParseJSON(readRepoFile("manifest.json")) as! [String: Any]

    let resources = Set(try #require(manifest["resources"] as? [String]))
    #expect(resources == Set(ResourceProvider.resources.map(\.uri)))

    let templates = Set(try #require(manifest["resource_templates"] as? [String]))
    #expect(templates == Set(ResourceProvider.templates.map(\.uriTemplate)))

    let description = try #require(manifest["description"] as? String)
    #expect(description.contains("\(ResourceProvider.resources.count) resources + \(ResourceProvider.templates.count) templates"))
}

@Test func testReadmeAndAPIDocsMatchPublicSurfaceAndRouting() throws {
    let readme = try readRepoFile("README.md")
    #expect(readme.contains("| Read resources | 14 static resources"))
    #expect(readme.contains("| Resource templates | 7 templates"))
    #expect(readme.contains("All 8 tools, 14 resources, 7 templates"))

    let api = try readRepoFile("docs/API.md")
    #expect(api.contains("| `toggle_cycle` | — | text | Accessibility → MIDIKeyCommands → CGEvent → MCU |"))
    #expect(api.contains("| `set_tempo` | `{ tempo: number }` (5–999, matches Logic's actual accepted range) | text | Accessibility |"))
}

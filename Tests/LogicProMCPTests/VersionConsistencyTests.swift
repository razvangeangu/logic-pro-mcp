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
        sourceVersion == "3.6.0",
        "version surfaces must match the published stable release — bump all packaging artefacts together"
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

@Test func testManifestResourceSurfaceMatchesPublishedStableRelease() throws {
    let manifest = try sharedParseJSON(readRepoFile("manifest.json")) as! [String: Any]

    // The manifest tools array is the published MCP-registry surface; it must equal the
    // server catalog exactly so it can never silently drift (e.g. omit logic_audio).
    let tools = Set(try #require(manifest["tools"] as? [String]))
    #expect(tools == Set(ServerCatalog.tools.map(\.name)))
    #expect(tools.count == 10)

    let resources = Set(try #require(manifest["resources"] as? [String]))
    #expect(resources == [
        "logic://system/health",
        "logic://transport/state",
        "logic://tracks",
        "logic://mixer",
        "logic://markers",
        "logic://project/info",
        "logic://midi/ports",
        "logic://mcu/state",
        "logic://library/inventory",
        "logic://stock-plugins",
        "logic://stock-plugins/census",
        "logic://stock-plugins/capabilities",
        "logic://workflow-skills",
        "logic://workflow-skills/schema",
    ])
    #expect(resources == Set(ResourceProvider.resources.map(\.uri)))

    let templates = Set(try #require(manifest["resource_templates"] as? [String]))
    #expect(templates == [
        "logic://tracks/{index}",
        "logic://tracks/{index}/regions",
        "logic://mixer/{strip}",
        "logic://stock-plugins/{id}",
        "logic://stock-plugins/search?query={query}",
        "logic://workflow-skills/{id}",
        "logic://workflow-skills/search?query={query}",
    ])
    #expect(templates == Set(ResourceProvider.templates.map(\.uriTemplate)))

    let description = try #require(manifest["description"] as? String)
    #expect(description.contains("10 tools + 14 resources + 7 templates"))
}

@Test func testReadmeAndAPIDocsMatchPublicSurfaceAndRouting() throws {
    let readme = try readRepoFile("README.md")
    #expect(readme.contains("| Read resources | 14 static resources"))
    #expect(readme.contains("| Resource templates | 7 templates"))
    #expect(readme.contains("All 10 tools, 14 resources, 7 templates"))

    let api = try readRepoFile("docs/API.md")
    #expect(api.contains("| `toggle_cycle` | — | text | Accessibility → MIDIKeyCommands → CGEvent → MCU |"))
    #expect(api.contains("| `set_tempo` | `{ tempo: number }` (5–999, matches Logic's actual accepted range) | text | Accessibility |"))
}

/// Issue #22 (thomas-doesburg): `brew install` broke at v3.4.6/v3.5.0 because
/// the Formula installed helper assets from the tarball root while the release
/// workflow stages them with repo-relative nested paths (`docs/SETUP.md`,
/// `Scripts/…`). PR #2 fixed the same failure class in the opposite direction
/// (formula nested / tarball flat), so this guards BOTH drift directions at
/// PR time: every `pkgshare.install` path must exist in the repo at exactly
/// the staged relative path, and every installed path (including
/// `bin.install`) must appear in the release workflow's tarball staging list.
/// The tag-time half of the guard lives in release.yml ("Verify Formula
/// install paths against tarball"), which re-asserts the same paths against
/// the actual built artifact before anything is published.
@Test func testFormulaInstallPathsMatchRepoAndReleaseStaging() throws {
    let formula = try readRepoFile("Formula/logic-pro-mcp.rb")
    let releaseWorkflow = try readRepoFile(".github/workflows/release.yml")

    func installPaths(_ directive: String) -> [String] {
        formula.components(separatedBy: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\(directive).install \"") else { return nil }
            let parts = trimmed.components(separatedBy: "\"")
            return parts.count >= 2 ? parts[1] : nil
        }
    }

    let pkgsharePaths = installPaths("pkgshare")
    let binPaths = installPaths("bin")
    #expect(
        pkgsharePaths.count == 5,
        "expected the 5 helper assets in Formula pkgshare.install; parser or Formula drifted: \(pkgsharePaths)"
    )
    #expect(binPaths == ["LogicProMCP"], "Formula bin.install drifted: \(binPaths)")

    let root = repositoryRootURL()
    for path in pkgsharePaths {
        #expect(
            !path.hasPrefix("/") && !path.contains(".."),
            "Formula install path '\(path)' must be a clean repo-relative path"
        )
        #expect(
            FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path),
            "Formula installs '\(path)' but no such file exists in the repo — the tarball stages repo-relative paths, so brew install would fail (issue #22)"
        )
    }
    for path in pkgsharePaths + binPaths {
        #expect(
            releaseWorkflow.contains(path),
            "Formula installs '\(path)' but release.yml does not stage it into the tarball (issue #22)"
        )
    }
}

// MARK: - R12 / AC1 / AC14 doc-lint
// The verified-apply-back contract must stay stated in the shipped docs so it
// cannot silently drift (the CI enforcement guardian flagged as missing).

@Test func testScripterSetParamDocumentedAsLegacyStateB() throws {
    // AC1 / R12: Scripter set_plugin_param is legacy unverified State B and must
    // NOT be presented as the verified apply-back solution.
    let api = try readRepoFile("docs/API.md")
    #expect(
        api.contains("legacy unverified State B"),
        "API.md must mark Scripter set_plugin_param as legacy unverified State B (R12/AC1)"
    )
    #expect(
        api.contains("logic_plugins.set_param_verified"),
        "API.md must point to logic_plugins.set_param_verified as the verified path (R12/AC1)"
    )
}

@Test func testInsertPluginDeprecationDocumented() throws {
    // AC14 / R12: logic_mixer.insert_plugin deprecated in favour of insert_verified.
    let changelog = try readRepoFile("CHANGELOG.md")
    #expect(
        changelog.lowercased().contains("insert_plugin` deprecated")
            || changelog.lowercased().contains("insert_plugin deprecated"),
        "CHANGELOG must note logic_mixer.insert_plugin deprecation (R12/AC14)"
    )
    #expect(
        changelog.contains("insert_verified"),
        "CHANGELOG must name logic_plugins.insert_verified as the go-forward path (R12/AC14)"
    )
}

@Test func testVerifiedApplyBackGuideExists() throws {
    // R12: the Thomas apply_moves guide must exist and document the gate + targeting.
    let guide = try readRepoFile("docs/guides/verified-apply-back.md")
    #expect(
        guide.contains("duplicate_applyback"),
        "verified-apply-back guide must document the duplicate_applyback gate (R12)"
    )
    #expect(
        guide.contains("get_inventory"),
        "verified-apply-back guide must document get_inventory targeting (R12)"
    )
}

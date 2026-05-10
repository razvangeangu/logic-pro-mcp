class LogicProMcp < Formula
  desc "MCP server for Logic Pro — the missing API"
  homepage "https://github.com/MongLong0214/logic-pro-mcp"
  # Single source of truth is Sources/LogicProMCP/Server/ServerConfig.swift
  # (ServerConfig.serverVersion). Bump both together.
  version "3.4.5-rc1"
  license "MIT"

  # arm64-native binary. Intel Macs run under Rosetta 2 — functional but
  # slower + with minor CoreMIDI / AX timing differences. The release workflow
  # with full Xcode + `swift build --arch arm64 --arch x86_64` would emit a
  # true universal binary; ADHOC local releases ship arm64 only. The tarball
  # is published under both `-arm64` and `-universal` names for backward
  # compatibility with taps that hardcoded the older URL — the bytes are
  # identical.
  #
  # NOTE: sha256 below is the v3.0.1 adhoc-signed tarball shipped on GitHub.
  #       Update every release from the published SHA256SUMS.txt.
  on_macos do
    url "https://github.com/MongLong0214/logic-pro-mcp/releases/download/v#{version}/LogicProMCP-macOS-universal.tar.gz"
    sha256 "40acc1a3a92a5999d412274f8caee04d9a5e215605d4dacdbf5018b40b2a34ec"
  end

  depends_on :macos => :sonoma

  # NOTE (v3.1.6): no `depends_on xcode:` — this Formula installs the
  # ADHOC pre-built arm64 binary published in the GitHub release; it does
  # not invoke `swift build` or any Apple toolchain. CLT-only hosts (macOS
  # Command Line Tools without a full Xcode.app install) install cleanly.
  # Source builds via `Package.swift` still require Xcode 15.0+ (Swift 6.0+),
  # but that is not the supported install path — see CONTRIBUTING.md.

  def install
    bin.install "LogicProMCP"
    # Helper assets shipped with the binary so users can complete Logic Pro
    # integration without re-cloning the repo.
    pkgshare.install "SETUP.md"
    pkgshare.install "install-keycmds.sh"
    pkgshare.install "uninstall-keycmds.sh"
    pkgshare.install "keycmd-preset.plist"
    pkgshare.install "LogicProMCP-Scripter.js"
  end

  def caveats
    <<~EOS
      Logic Pro MCP Server is installed at #{bin}/LogicProMCP.

      Register with Claude Code:
        claude mcp add --scope user logic-pro -- LogicProMCP

      Check macOS permissions:
        LogicProMCP --check-permissions

      Complete Logic Pro integration (MCU, Key Commands, Scripter):
        open #{pkgshare}/SETUP.md

      Approve manual-validation channels after Logic Pro setup:
        LogicProMCP --approve-channel MIDIKeyCommands
        LogicProMCP --approve-channel Scripter
    EOS
  end

  test do
    # Verify the binary runs and prints the expected report shape on
    # `--check-permissions`. Exit code is 0 when both Accessibility and
    # Logic Automation are granted (typical Logic-installed dev box) and
    # non-zero when at least one is missing (typical CI). Don't constrain
    # the test to a specific code — both are valid; the report contents
    # are the contract this test guards.
    output = shell_output("#{bin}/LogicProMCP --check-permissions 2>&1; echo \"exit=$?\"")
    assert_match(/Accessibility/, output)
    assert_match(/Automation/, output)
    assert_match(/exit=[01]/, output, "exit code should be 0 (granted) or 1 (missing)")
  end
end

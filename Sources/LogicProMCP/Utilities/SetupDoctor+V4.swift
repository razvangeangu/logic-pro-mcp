import Foundation

extension SetupDoctor {
    enum DoctorProfile: String, Codable, Sendable, CaseIterable {
        case auto
        case core
        case mixer
        case keycmd
        case legacyScripter = "legacy-scripter"
        case full
    }

    enum ClientProfile: String, Codable, Sendable, CaseIterable {
        case auto
        case claudeCode = "claude-code"
        case claudeDesktop = "claude-desktop"
        case cursor
        case vscode
        case terminal
        case custom
    }

    enum CapabilityStatus: String, Codable, Sendable {
        case ready
        case notReady = "not_ready"
        case unknownLiveVerifyRequired = "unknown_live_verify_required"
        case notInProfile = "not_in_profile"
    }

    struct CapabilityReadiness: Codable, Equatable, Sendable {
        let status: CapabilityStatus
        let checks: [String]
        let liveVerification: String?

        enum CodingKeys: String, CodingKey {
            case status
            case checks
            case liveVerification = "live_verification"
        }
    }

    enum PathEvidencePolicy: Sendable {
        case homeRelative
        case basenameOnly
        case hidden
    }

    enum EvidenceValue: Sendable {
        case bool(Bool)
        case int(Int)
        case enumValue(String)
        case version(String)
        case path(String, PathEvidencePolicy)
        case basename(String)
        case sensitive
    }

    struct SemanticVersion: Equatable, Comparable, Sendable {
        let major: Int
        let minor: Int
        let patch: Int
        let prerelease: String?
        let build: String?

        init?(_ raw: String) {
            var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("v") || value.hasPrefix("V") {
                value.removeFirst()
            }
            let buildParts = value.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
            let withoutBuild = String(buildParts[0])
            build = buildParts.count == 2 && !buildParts[1].isEmpty ? String(buildParts[1]) : nil
            let prereleaseParts = withoutBuild.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            let core = prereleaseParts[0].split(separator: ".", omittingEmptySubsequences: false)
            guard core.count == 3,
                  let major = Int(core[0]), major >= 0,
                  let minor = Int(core[1]), minor >= 0,
                  let patch = Int(core[2]), patch >= 0,
                  core.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
                return nil
            }
            let prereleaseValue = prereleaseParts.count == 2 ? String(prereleaseParts[1]) : nil
            if prereleaseValue == "" { return nil }
            self.major = major
            self.minor = minor
            self.patch = patch
            prerelease = prereleaseValue
        }

        var normalizedCore: String {
            "\(major).\(minor).\(patch)"
        }

        static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
            if lhs.major != rhs.major { return lhs.major < rhs.major }
            if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
            if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
            switch (lhs.prerelease, rhs.prerelease) {
            case (nil, nil):
                return false
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            case let (left?, right?):
                return left < right
            }
        }
    }

    static func selectedDoctorProfile(
        arguments: [String],
        runtime: Runtime,
        approvals: [ManualValidationChannel: ManualValidationApproval]
    ) -> (DoctorProfile, String) {
        if let raw = optionValue("--profile", in: arguments),
           let profile = DoctorProfile(rawValue: raw) {
            if profile == .auto {
                let inferred = inferredDoctorProfile(runtime: runtime, approvals: approvals)
                return (inferred.0, "explicit_auto_\(inferred.1)")
            }
            return (profile, "explicit_flag")
        }
        return inferredDoctorProfile(runtime: runtime, approvals: approvals)
    }

    private static func inferredDoctorProfile(
        runtime: Runtime,
        approvals: [ManualValidationChannel: ManualValidationApproval]
    ) -> (DoctorProfile, String) {
        let approvedChannels = Set(
            approvals.compactMap { channel, approval -> ManualValidationChannel? in
                switch approval.kind {
                case .approved, .intentionallySkipped:
                    return channel
                }
            }
        )
        if approvedChannels == Set(ManualValidationChannel.allCases) {
            return (.full, "manual_store_all_channels")
        }
        if approvedChannels == [.midiKeyCommands] {
            return (.keycmd, "manual_store_midi_key_commands")
        }
        if approvedChannels == [.scripter] {
            return (.legacyScripter, "manual_store_scripter")
        }
        let context = runtime.launchContext().context
        if context == "claude_code" || context == "claude_desktop" || context == "cursor" || context == "vscode" {
            return (.core, "launch_context_default_core")
        }
        return (.core, "default_core")
    }

    static func selectedClientProfile(
        arguments: [String],
        runtime: Runtime,
        claudeRegistration: ClaudeRegistration
    ) -> (ClientProfile, String) {
        if let raw = optionValue("--client", in: arguments),
           let profile = ClientProfile(rawValue: raw) {
            return profile == .auto ? inferredClientProfile(runtime: runtime, claudeRegistration: claudeRegistration) : (profile, "explicit_flag")
        }
        return inferredClientProfile(runtime: runtime, claudeRegistration: claudeRegistration)
    }

    private static func inferredClientProfile(
        runtime: Runtime,
        claudeRegistration: ClaudeRegistration
    ) -> (ClientProfile, String) {
        let context = runtime.launchContext().context
        switch context {
        case "claude_code": return (.claudeCode, "launch_context")
        case "claude_desktop": return (.claudeDesktop, "launch_context")
        case "cursor": return (.cursor, "launch_context")
        case "vscode": return (.vscode, "launch_context")
        case "terminal": return (.terminal, "launch_context")
        default: break
        }
        if case .registered = claudeRegistration {
            return (.claudeCode, "registration_config")
        }
        switch runtime.readClaudeDesktopRegistration() {
        case .registered:
            return (.claudeDesktop, "registration_config")
        case .notRegistered, .configUnavailable:
            return (.custom, "fallback_custom")
        }
    }

    static func optionValue(_ option: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: option), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    static func isProfileRequired(_ checkID: String, profile: DoctorProfile) -> Bool {
        switch profile {
        case .full:
            return true
        case .core:
            return ![
                "channels.manual_validation",
                "channels.keycmd_reference",
                "channels.mcu_wiring_hint",
            ].contains(checkID)
        case .mixer:
            return ![
                "channels.manual_validation",
                "channels.keycmd_reference",
                "channels.mcu_wiring_hint",
            ].contains(checkID)
        case .keycmd:
            return checkID != "channels.mcu_wiring_hint"
        case .legacyScripter:
            return ![
                "channels.keycmd_reference",
                "channels.mcu_wiring_hint",
            ].contains(checkID)
        case .auto:
            return isProfileRequired(checkID, profile: .core)
        }
    }

    static func profileRequiredCheckIDs(for profile: DoctorProfile) -> Set<String> {
        Set(orderedCheckIDs.filter { isProfileRequired($0, profile: profile) })
    }

    static func capabilities(for checks: [Check], profile: DoctorProfile) -> [String: CapabilityReadiness] {
        let definitions: [(String, [String], Set<DoctorProfile>, String?)] = [
            ("core_transport", ["binary.path", "binary.executable", "permissions.accessibility", "permissions.post_event_access", "logic.installation", "logic.version_support", "logic.application_state"], [.core, .mixer, .keycmd, .legacyScripter, .full], nil),
            ("track_management", ["binary.path", "binary.executable", "permissions.accessibility", "permissions.post_event_access", "logic.installation", "logic.version_support", "logic.application_state", "permissions.automation_logic_pro", "logic.blocking_dialog"], [.core, .mixer, .full], nil),
            ("midi_import", ["binary.path", "binary.executable", "permissions.accessibility", "permissions.post_event_access", "logic.installation", "logic.version_support", "logic.application_state", "permissions.automation_system_events"], [.full], nil),
            ("mixer_ax", ["binary.path", "binary.executable", "permissions.accessibility", "permissions.post_event_access", "logic.installation", "logic.version_support", "logic.application_state", "permissions.automation_logic_pro", "logic.blocking_dialog"], [.mixer, .full], nil),
            ("mixer_mcu", ["binary.path", "binary.executable", "permissions.accessibility", "permissions.post_event_access", "logic.installation", "logic.version_support", "logic.application_state", "channels.mcu_wiring_hint"], [.full], "logic://system/health mcu.connected"),
            ("project_lifecycle", ["binary.path", "binary.executable", "permissions.accessibility", "permissions.post_event_access", "logic.installation", "logic.version_support", "logic.application_state", "permissions.automation_logic_pro", "permissions.automation_system_events"], [.core, .mixer, .full], nil),
            ("keycmd_only_ops", ["binary.path", "binary.executable", "permissions.accessibility", "permissions.post_event_access", "logic.installation", "logic.version_support", "logic.application_state", "channels.keycmd_reference", "channels.manual_validation"], [.keycmd, .full], nil),
            ("legacy_scripter", ["binary.path", "binary.executable", "permissions.accessibility", "permissions.post_event_access", "logic.installation", "logic.version_support", "logic.application_state", "channels.manual_validation"], [.legacyScripter, .full], nil),
            ("verified_plugin_applyback", ["binary.path", "binary.executable", "permissions.accessibility", "permissions.post_event_access", "logic.installation", "logic.version_support", "logic.application_state", "permissions.automation_logic_pro", "logic.blocking_dialog"], [.mixer, .full], nil),
        ]
        let byID = Dictionary(uniqueKeysWithValues: checks.map { ($0.id, $0) })
        return Dictionary(uniqueKeysWithValues: definitions.map { name, required, profiles, liveVerification in
            guard profiles.contains(profile) else {
                return (name, CapabilityReadiness(status: .notInProfile, checks: required, liveVerification: liveVerification))
            }
            let statuses = required.compactMap { byID[$0]?.status }
            let missingRequired = statuses.count != required.count
            let status: CapabilityStatus
            if missingRequired || statuses.contains(.fail) || statuses.contains(.warn) {
                status = .notReady
            } else if statuses.contains(.manual) || statuses.contains(.skipped) {
                status = .unknownLiveVerifyRequired
            } else if name == "mixer_mcu" {
                status = .unknownLiveVerifyRequired
            } else {
                status = .ready
            }
            return (name, CapabilityReadiness(status: status, checks: required, liveVerification: liveVerification))
        })
    }

    static func buildEvidence(_ fields: [String: EvidenceValue]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: fields.map { key, value in
            (key, renderEvidenceValue(value))
        })
    }

    static func renderEvidenceValue(_ value: EvidenceValue) -> String {
        switch value {
        case let .bool(raw):
            return String(raw)
        case let .int(raw):
            return String(raw)
        case let .enumValue(raw), let .version(raw):
            return raw
        case let .path(raw, policy):
            switch policy {
            case .homeRelative:
                return homeRelativePath(raw)
            case .basenameOnly:
                return URL(fileURLWithPath: raw).lastPathComponent
            case .hidden:
                return "hidden"
            }
        case let .basename(raw):
            return URL(fileURLWithPath: raw).lastPathComponent
        case .sensitive:
            return "redacted"
        }
    }

    static func homeRelativePath(_ value: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return value.replacingOccurrences(of: home, with: "~")
    }
}

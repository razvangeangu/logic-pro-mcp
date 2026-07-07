import Foundation

enum AppleScriptErrorClassifier {
    static let systemEventsAutomationDeniedHint =
        "System Events Automation is denied for the process responsible for launching this server (a launcher-permission gap, not a Logic limitation). Grant it in System Settings > Privacy & Security > Automation, or run the server/harness under a responsible app that already has it (Terminal, iTerm, or your editor). Logic Pro automation being granted is separate and not sufficient."

    static let systemEventsAutomationDeniedCoreMatchTokens = ["-1743", "errAEEventNotPermitted", "not authorized to send Apple events to System Events", "not allowed to send Apple events to System Events", "System Events", "systemevents"]

    static func isSystemEventsAutomationDenied(_ output: String) -> Bool {
        let lowercased = output.lowercased()
        let hasPermissionCode = lowercased.contains(systemEventsAutomationDeniedCoreMatchTokens[0])
            || lowercased.contains(systemEventsAutomationDeniedCoreMatchTokens[1].lowercased())
        // Real osascript stderr sometimes omits -1743; the full System Events TCC denial phrase is still definitive.
        let hasCanonicalSystemEventsPermissionError = lowercased.contains(systemEventsAutomationDeniedCoreMatchTokens[2].lowercased())
            || lowercased.contains(systemEventsAutomationDeniedCoreMatchTokens[3].lowercased())
        let referencesSystemEvents = lowercased.contains(systemEventsAutomationDeniedCoreMatchTokens[4].lowercased())
            || lowercased.contains(systemEventsAutomationDeniedCoreMatchTokens[5])
        return hasCanonicalSystemEventsPermissionError || (hasPermissionCode && referencesSystemEvents)
    }
}

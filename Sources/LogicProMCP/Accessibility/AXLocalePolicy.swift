import ApplicationServices
import Foundation

/// Central policy for unavoidable Logic UI text matching.
///
/// Callers should prefer AX structure, identifiers, roles, geometry, selected
/// state, and post-write readback. Use these label sets only where Logic exposes
/// no stable non-localized AX handle, and keep State A gated by independent
/// readback on write paths.
enum AXLocalePolicy {
    enum MatchMode {
        case exact
        case prefix
        case contains
    }

    struct LabelSet: Sendable, Equatable {
        let canonical: String
        let variants: [String]
        let rationale: String

        init(canonical: String, variants: [String], rationale: String) {
            self.canonical = canonical
            self.variants = variants
            self.rationale = rationale
        }

        var labels: [String] {
            var result: [String] = []
            for label in [canonical] + variants {
                let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, !result.contains(trimmed) {
                    result.append(trimmed)
                }
            }
            return result
        }

        func matches(_ text: String?, mode: MatchMode = .exact) -> Bool {
            guard let text else { return false }
            let candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !candidate.isEmpty else { return false }

            return labels.contains { label in
                switch mode {
                case .exact:
                    candidate.caseInsensitiveCompare(label) == .orderedSame
                case .prefix:
                    candidate.range(
                        of: label,
                        options: [.anchored, .caseInsensitive, .diacriticInsensitive]
                    ) != nil
                case .contains:
                    candidate.range(
                        of: label,
                        options: [.caseInsensitive, .diacriticInsensitive]
                    ) != nil
                }
            }
        }
    }

    struct MenuPath: Sendable, Equatable {
        let bar: LabelSet
        let item: LabelSet
        let itemMode: MatchMode

        init(bar: LabelSet, item: LabelSet, itemMode: MatchMode = .exact) {
            self.bar = bar
            self.item = item
            self.itemMode = itemMode
        }
    }

    static let viewMenuBar = LabelSet(
        canonical: "View",
        variants: ["보기"],
        rationale: "Top-level menu titles expose no stable AXIdentifier in Logic."
    )

    static let showMixerMenuItem = LabelSet(
        canonical: "Show Mixer",
        variants: ["믹서 보기"],
        rationale: "Used only as a best-effort mixer reveal before structural mixer readback."
    )

    static let windowMenuBar = LabelSet(
        canonical: "Window",
        variants: ["윈도우"],
        rationale: "Top-level menu titles expose no stable AXIdentifier in Logic."
    )

    static let hideAllPluginWindowsMenuItem = LabelSet(
        canonical: "Hide All Plug-in Windows",
        variants: ["모든 플러그인 윈도우 가리기"],
        rationale: "Best-effort cleanup so stale plugin windows do not steal later menu focus."
    )

    static let editMenuBar = LabelSet(
        canonical: "Edit",
        variants: ["편집"],
        rationale: "Undo is menu-only in the rollback path; post-undo inventory readback verifies outcome."
    )

    static let undoMenuItemPrefix = LabelSet(
        canonical: "Undo",
        variants: ["실행 취소"],
        rationale: "Menu item includes the operation name after the localized Undo prefix."
    )

    static let goToPositionDialogTitle = LabelSet(
        canonical: "Go to Position",
        variants: ["위치로 이동"],
        rationale: "Used only to dismiss a stale dialog before another verified operation."
    )

    static let cancelButton = LabelSet(
        canonical: "Cancel",
        variants: ["취소"],
        rationale: "Dialog dismissal fallback; no success state is inferred from this click."
    )

    static let saveConfirmationButton = LabelSet(
        canonical: "Save",
        variants: ["저장", "OK", "확인"],
        rationale: "Save As dialog commit button; file existence verifies the result."
    )

    static let pluginFormatLeafPriority: [LabelSet] = [
        LabelSet(canonical: "Stereo", variants: ["스테레오"], rationale: "Plugin format leaf after exact plugin selection."),
        LabelSet(canonical: "Mono", variants: ["모노"], rationale: "Plugin format leaf after exact plugin selection."),
        LabelSet(canonical: "Mono->Stereo", variants: ["모노->스테레오"], rationale: "Plugin format leaf after exact plugin selection."),
        LabelSet(canonical: "Dual Mono", variants: ["듀얼 모노"], rationale: "Plugin format leaf after exact plugin selection."),
    ]

    static let showMixerMenuPath = MenuPath(bar: viewMenuBar, item: showMixerMenuItem)
    static let hidePluginWindowsMenuPath = MenuPath(bar: windowMenuBar, item: hideAllPluginWindowsMenuItem)
    static let editUndoMenuPath = MenuPath(bar: editMenuBar, item: undoMenuItemPrefix, itemMode: .prefix)

    static func elementLabel(_ element: AXUIElement, runtime: AXHelpers.Runtime) -> String? {
        for text in [
            AXHelpers.getTitle(element, runtime: runtime),
            AXHelpers.getDescription(element, runtime: runtime),
        ] {
            if let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
               !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    static func elementMatches(
        _ element: AXUIElement,
        _ labels: LabelSet,
        mode: MatchMode = .exact,
        runtime: AXHelpers.Runtime
    ) -> Bool {
        labels.matches(AXHelpers.getTitle(element, runtime: runtime), mode: mode)
            || labels.matches(AXHelpers.getDescription(element, runtime: runtime), mode: mode)
    }

    static func findMenuBarItem(
        in menuBar: AXUIElement,
        matching labels: LabelSet,
        runtime: AXHelpers.Runtime
    ) -> AXUIElement? {
        AXHelpers.getChildren(menuBar, runtime: runtime).first {
            elementMatches($0, labels, runtime: runtime)
        }
    }

    static func findMenuItem(
        under menuBarItem: AXUIElement,
        matching labels: LabelSet,
        mode: MatchMode = .exact,
        maxDepth: Int = 5,
        runtime: AXHelpers.Runtime
    ) -> AXUIElement? {
        AXHelpers.findAllDescendants(
            of: menuBarItem,
            role: kAXMenuItemRole as String,
            maxDepth: maxDepth,
            runtime: runtime
        ).first {
            elementMatches($0, labels, mode: mode, runtime: runtime)
        }
    }

    static func findDescendant(
        of element: AXUIElement,
        role: String,
        matching labels: LabelSet,
        mode: MatchMode = .exact,
        maxDepth: Int = 5,
        runtime: AXHelpers.Runtime
    ) -> AXUIElement? {
        AXHelpers.findAllDescendants(of: element, role: role, maxDepth: maxDepth, runtime: runtime).first {
            elementMatches($0, labels, mode: mode, runtime: runtime)
        }
    }
}

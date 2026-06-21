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
        /// Whole-string equality WITHOUT whitespace trimming, case-insensitive.
        /// Preserves the raw `desc == label` / `desc.lowercased() == label`
        /// semantics used by structural control-bar / track-header locators that
        /// historically compared the AX description verbatim. Distinct from
        /// `.exact`, which trims surrounding whitespace.
        case exactStrict
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

            // `.exactStrict` compares the verbatim string (no trim) so it
            // preserves the historical `desc == label` semantics exactly. All
            // other modes trim surrounding whitespace, matching the existing
            // migrated policy behavior.
            if mode == .exactStrict {
                guard !text.isEmpty else { return false }
                return labels.contains { text.caseInsensitiveCompare($0) == .orderedSame }
            }

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
                case .exactStrict:
                    candidate.caseInsensitiveCompare(label) == .orderedSame
                }
            }
        }

        /// True if `haystack` contains ANY label as a case-insensitive substring.
        /// Preserves the existing `combined.contains(token)` control flow where a
        /// pre-built, already-lowercased aggregate string is scanned for any of a
        /// set of localized tokens. The caller keeps its own AX traversal and
        /// structural ordering; only the token list moves into policy.
        func containsAny(in haystack: String) -> Bool {
            labels.contains { label in
                haystack.range(of: label, options: [.caseInsensitive, .diacriticInsensitive]) != nil
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

    // MARK: - Read-only locator labels (Phase 2, issue #60)
    //
    // The label sets below back read-only AX locators / state extractors. None
    // of them gate a State-A success: they identify which control to read, or
    // classify a description string. Mutating callers still verify via
    // independent readback. They are centralized here so the EN/KO token pairs
    // live in one audited place; each preserves the EXACT match mode and token
    // order of its original call site.

    // --- Transport control identification (read-only, `.contains` semantics) ---

    static let transportPlayControl = LabelSet(
        canonical: "play",
        variants: ["재생"],
        rationale: "Identifies the Play transport control when reading TransportState; read-only."
    )

    static let transportRecordControl = LabelSet(
        canonical: "record",
        variants: ["녹음"],
        rationale: "Identifies the Record transport control; excluded by arm-tokens at the call site; read-only."
    )

    static let transportCycleControl = LabelSet(
        canonical: "cycle",
        variants: ["loop", "사이클"],
        rationale: "Identifies the Cycle/Loop transport control; read-only."
    )

    static let transportMetronomeControl = LabelSet(
        canonical: "metronome",
        variants: ["click", "메트로놈", "클릭"],
        rationale: "Identifies the Metronome/Click transport control; read-only."
    )

    /// Record-arm disambiguation tokens. Their PRESENCE on a Record control
    /// EXCLUDES it from being treated as the transport Record button.
    static let transportRecordArmExclusion = LabelSet(
        canonical: "arm",
        variants: ["활성화"],
        rationale: "Negative guard: distinguishes per-track record-arm from transport Record; read-only."
    )

    static let tempoFieldLabel = LabelSet(
        canonical: "tempo",
        variants: ["bpm", "템포"],
        rationale: "Identifies a tempo text field/slider description; read-only."
    )

    static let playheadPositionFieldLabel = LabelSet(
        canonical: "position",
        variants: ["재생헤드 위치"],
        rationale: "Identifies the playhead position text field description; read-only."
    )

    // --- Control-bar slider locators (read-only, verbatim `.exactStrict`) ---

    static let controlBarGroupLabel = LabelSet(
        canonical: "control bar",
        variants: ["컨트롤 막대"],
        rationale: "Identifies the control-bar AXGroup by description; read-only locator."
    )

    static let barSliderLabel = LabelSet(
        canonical: "bar",
        variants: ["마디"],
        rationale: "Identifies the bar slider in the control bar; verbatim description match; read-only."
    )

    static let beatSliderLabel = LabelSet(
        canonical: "beat",
        variants: ["비트"],
        rationale: "Identifies the beat slider in the control bar; verbatim description match; read-only."
    )

    /// Tempo slider description for `findTempoSlider` (verbatim `.exactStrict`).
    /// Includes `bpm` because that locator explicitly accepts `desc == "bpm"`.
    static let tempoSliderLabel = LabelSet(
        canonical: "tempo",
        variants: ["bpm", "템포"],
        rationale: "Identifies the tempo slider; verbatim (lowercased) description match; read-only."
    )

    /// Tempo slider description for the read-only `extractTransportState` slider
    /// loop, which historically matched ONLY `tempo`/`템포` via `.contains`
    /// (NOT `bpm`). Kept distinct from `tempoSliderLabel` to preserve behavior.
    static let tempoSliderContainsLabel = LabelSet(
        canonical: "tempo",
        variants: ["템포"],
        rationale: "Identifies the tempo slider in TransportState extraction; substring match without bpm; read-only."
    )

    /// #109: arrange Horizontal-Zoom slider (writable AXValue). EN canonical +
    /// KO variant; matched by description substring.
    static let horizontalZoomSlider = LabelSet(
        canonical: "Horizontal Zoom",
        variants: ["가로 확대/축소", "가로 확대"],
        rationale: "Locates the arrange horizontal-zoom AXSlider for verified set_zoom writes; description substring match."
    )

    // --- Track-header read-only locators ---

    static let trackMuteButton = LabelSet(
        canonical: "Mute",
        variants: ["음소거"],
        rationale: "Identifies the track Mute button by description substring; read-only state extraction."
    )

    static let trackSoloButton = LabelSet(
        canonical: "Solo",
        variants: ["솔로"],
        rationale: "Identifies the track Solo button by description substring; read-only state extraction."
    )

    static let trackRecordButton = LabelSet(
        canonical: "Record",
        variants: ["Rec", "녹음 활성화", "레코드 활성화"],
        rationale: "Identifies the track Record/arm button by description substring; read-only state extraction."
    )

    /// Per-track record-enable AXCheckBox description. Verbatim match preserves
    /// the original `desc == "녹음 활성화" || ...` locator semantics.
    static let trackRecordEnableCheckbox = LabelSet(
        canonical: "녹음 활성화",
        variants: ["Record Enable", "Record"],
        rationale: "Locates the per-track record-enable AXCheckBox; verbatim description match; read-only locator."
    )

    // --- Plugin Setting popup locator (read-only, `.contains`) ---

    static let settingPopupValue = LabelSet(
        canonical: "Preset",
        variants: ["프리셋", "Default", "기본"],
        rationale: "Identifies the plugin Setting AXPopUpButton by its value substring; read-only locator."
    )

    static let showMixerMenuPath = MenuPath(bar: viewMenuBar, item: showMixerMenuItem)
    static let hidePluginWindowsMenuPath = MenuPath(bar: windowMenuBar, item: hideAllPluginWindowsMenuItem)
    static let editUndoMenuPath = MenuPath(bar: editMenuBar, item: undoMenuItemPrefix, itemMode: .prefix)

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

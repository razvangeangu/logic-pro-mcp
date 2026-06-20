@preconcurrency import ApplicationServices
import Testing
@testable import LogicProMCP

private func addPolicyMenuItem(
    _ builder: FakeAXRuntimeBuilder,
    _ id: Int,
    title: String,
    children: [AXUIElement] = []
) -> AXUIElement {
    let item = builder.element(id)
    builder.setAttribute(item, kAXRoleAttribute as String, kAXMenuItemRole as String)
    builder.setAttribute(item, kAXTitleAttribute as String, title)
    builder.setChildren(item, children)
    return item
}

@Suite("AX locale policy")
struct AXLocalePolicyTests {
    @Test("localized label sets cover English and Korean without broad false positives")
    func labelSetMatching() {
        #expect(AXLocalePolicy.cancelButton.matches("Cancel"))
        #expect(AXLocalePolicy.cancelButton.matches("취소"))
        #expect(!AXLocalePolicy.cancelButton.matches("Do Not Save"))

        #expect(AXLocalePolicy.saveConfirmationButton.matches("Save"))
        #expect(AXLocalePolicy.saveConfirmationButton.matches("저장"))
        #expect(AXLocalePolicy.saveConfirmationButton.matches("확인"))
        #expect(!AXLocalePolicy.saveConfirmationButton.matches("Don't Save"))

        #expect(AXLocalePolicy.undoMenuItemPrefix.matches("Undo Insert Plug-in", mode: .prefix))
        #expect(AXLocalePolicy.undoMenuItemPrefix.matches("실행 취소 플러그인 삽입", mode: .prefix))
        #expect(!AXLocalePolicy.undoMenuItemPrefix.matches("Redo Insert Plug-in", mode: .prefix))
    }

    @Test("menu path lookup resolves English and Korean titles through one policy")
    func menuPathLookup() {
        let builder = FakeAXRuntimeBuilder()
        let menuBar = builder.element(1)
        let view = addPolicyMenuItem(builder, 2, title: "View")
        let showMixer = addPolicyMenuItem(builder, 3, title: "Show Mixer")
        let koreanWindow = addPolicyMenuItem(builder, 4, title: "윈도우")
        let hidePlugins = addPolicyMenuItem(builder, 5, title: "모든 플러그인 윈도우 가리기")
        builder.setChildren(menuBar, [view, koreanWindow])
        builder.setChildren(view, [showMixer])
        builder.setChildren(koreanWindow, [hidePlugins])

        let runtime = builder.makeAXRuntime()
        let viewMatch = AXLocalePolicy.findMenuBarItem(
            in: menuBar,
            matching: AXLocalePolicy.viewMenuBar,
            runtime: runtime
        )
        let windowMatch = AXLocalePolicy.findMenuBarItem(
            in: menuBar,
            matching: AXLocalePolicy.windowMenuBar,
            runtime: runtime
        )

        #expect(viewMatch == view)
        #expect(windowMatch == koreanWindow)
        #expect(AXLocalePolicy.findMenuItem(
            under: view,
            matching: AXLocalePolicy.showMixerMenuItem,
            runtime: runtime
        ) == showMixer)
        #expect(AXLocalePolicy.findMenuItem(
            under: koreanWindow,
            matching: AXLocalePolicy.hideAllPluginWindowsMenuItem,
            runtime: runtime
        ) == hidePlugins)
    }

    @Test("element matching checks title and description")
    func elementMatchingUsesTitleAndDescription() {
        let builder = FakeAXRuntimeBuilder()
        let titleButton = builder.element(20)
        let descriptionButton = builder.element(21)
        builder.setAttribute(titleButton, kAXRoleAttribute as String, kAXButtonRole as String)
        builder.setAttribute(descriptionButton, kAXRoleAttribute as String, kAXButtonRole as String)
        builder.setAttribute(titleButton, kAXTitleAttribute as String, "Cancel")
        builder.setAttribute(descriptionButton, kAXDescriptionAttribute as String, "취소")

        let runtime = builder.makeAXRuntime()

        #expect(AXLocalePolicy.elementMatches(titleButton, AXLocalePolicy.cancelButton, runtime: runtime))
        #expect(AXLocalePolicy.elementMatches(descriptionButton, AXLocalePolicy.cancelButton, runtime: runtime))
    }
}

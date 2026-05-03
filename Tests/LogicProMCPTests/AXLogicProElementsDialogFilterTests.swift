@preconcurrency import ApplicationServices
import Testing
@testable import LogicProMCP

/// v3.1.1 (P1-2) — verify `mainWindow()` skips modal dialog windows
/// (subrole `AXDialog` / `AXSystemDialog`) and prefers the arrange window
/// (the one that owns the Track Headers group). Pre-3.1.1 the function
/// returned `kAXMainWindowAttribute` directly; macOS reports the topmost
/// dialog as the main window while it is up, so callers walking down from
/// it found no transport / no tracks and the StateCache wrote a phantom
/// "empty project" payload.

@Test func testMainWindowSkipsDialogWindows() {
    let builder = FakeAXRuntimeBuilder()
    let app = builder.element(1)
    let dialog = builder.element(2)
    let arrange = builder.element(3)
    let trackHeadersGroup = builder.element(4)

    // Dialog window — must be skipped.
    builder.setAttribute(dialog, kAXSubroleAttribute as String, kAXDialogSubrole as String)

    // Arrange window — has Track Headers group descendant.
    builder.setChildren(arrange, [trackHeadersGroup])
    builder.setAttribute(trackHeadersGroup, kAXRoleAttribute as String, kAXGroupRole as String)
    builder.setAttribute(trackHeadersGroup, "AXDescription" as String, "트랙 헤더")

    // Windows array exposes both. macOS would set kAXMainWindowAttribute to
    // the dialog (the modal sheet steals "main"); the new logic must prefer
    // the arrange window regardless.
    builder.setAttribute(app, kAXWindowsAttribute as String, [dialog, arrange])
    builder.setAttribute(app, kAXMainWindowAttribute as String, dialog)

    let runtime = builder.makeLogicRuntime(appElement: app)
    #expect(AXLogicProElements.mainWindow(runtime: runtime) == arrange)
}

@Test func testMainWindowSkipsSystemDialogWindows() {
    let builder = FakeAXRuntimeBuilder()
    let app = builder.element(1)
    let bouncePanel = builder.element(2)
    let arrange = builder.element(3)
    let trackHeadersGroup = builder.element(4)

    // System dialog (e.g. macOS file-open panel routed through AppKit).
    builder.setAttribute(bouncePanel, kAXSubroleAttribute as String, kAXSystemDialogSubrole as String)

    builder.setChildren(arrange, [trackHeadersGroup])
    builder.setAttribute(trackHeadersGroup, kAXRoleAttribute as String, kAXGroupRole as String)
    builder.setAttribute(trackHeadersGroup, "AXDescription" as String, "Track Headers")

    builder.setAttribute(app, kAXWindowsAttribute as String, [bouncePanel, arrange])
    builder.setAttribute(app, kAXMainWindowAttribute as String, bouncePanel)

    let runtime = builder.makeLogicRuntime(appElement: app)
    #expect(AXLogicProElements.mainWindow(runtime: runtime) == arrange)
}

@Test func testMainWindowFallsBackToFirstNonDialogWindow() {
    // No window carries the Track Headers group (e.g. Library detached
    // pane in front, arrange minimized). We still skip dialogs and return
    // the first non-dialog so downstream lookups have something to walk.
    let builder = FakeAXRuntimeBuilder()
    let app = builder.element(1)
    let dialog = builder.element(2)
    let libraryPane = builder.element(3)

    builder.setAttribute(dialog, kAXSubroleAttribute as String, kAXDialogSubrole as String)
    // libraryPane has no subrole — treated as a regular window.

    builder.setAttribute(app, kAXWindowsAttribute as String, [dialog, libraryPane])

    let runtime = builder.makeLogicRuntime(appElement: app)
    #expect(AXLogicProElements.mainWindow(runtime: runtime) == libraryPane)
}

@Test func testMainWindowFallsBackToLegacyAttributeWhenNoWindowsArray() {
    // Test doubles that don't set kAXWindowsAttribute (every existing
    // AXLogicProElementsTests.swift case) must still work via the legacy
    // kAXMainWindowAttribute fallback.
    let builder = FakeAXRuntimeBuilder()
    let app = builder.element(1)
    let window = builder.element(2)
    builder.setAttribute(app, kAXMainWindowAttribute as String, window)

    let runtime = builder.makeLogicRuntime(appElement: app)
    #expect(AXLogicProElements.mainWindow(runtime: runtime) == window)
}

@Test func testDialogPresentDetectsActiveModal() {
    let builder = FakeAXRuntimeBuilder()
    let app = builder.element(1)
    let dialog = builder.element(2)
    let arrange = builder.element(3)

    builder.setAttribute(dialog, kAXSubroleAttribute as String, kAXDialogSubrole as String)
    builder.setAttribute(app, kAXWindowsAttribute as String, [dialog, arrange])

    let runtime = builder.makeLogicRuntime(appElement: app)
    #expect(AXLogicProElements.dialogPresent(runtime: runtime) == true)
}

@Test func testDialogPresentReturnsFalseWhenNoDialogs() {
    let builder = FakeAXRuntimeBuilder()
    let app = builder.element(1)
    let arrange = builder.element(2)
    builder.setAttribute(app, kAXWindowsAttribute as String, [arrange])

    let runtime = builder.makeLogicRuntime(appElement: app)
    #expect(AXLogicProElements.dialogPresent(runtime: runtime) == false)
}

@Test func testDialogPresentReturnsFalseWhenNoWindowsExposed() {
    // No kAXWindowsAttribute set — treated as "no dialogs known".
    let builder = FakeAXRuntimeBuilder()
    let app = builder.element(1)
    let runtime = builder.makeLogicRuntime(appElement: app)
    #expect(AXLogicProElements.dialogPresent(runtime: runtime) == false)
}

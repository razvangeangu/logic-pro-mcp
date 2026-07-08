#!/usr/bin/env swift
import AppKit
import ApplicationServices
import Foundation

struct Snapshot: Encodable {
    let frontmost_app: String?
    let frontmost_bundle_id: String?
    let logic_window_names: [String]
    let logic_menu_items: [String]
    let blocking_dialog_present: Bool
    let error: String?
}

func axAttribute<T>(_ element: AXUIElement, _ attribute: String) -> T? {
    var value: AnyObject?
    let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard result == .success else { return nil }
    return value as? T
}

func title(of element: AXUIElement) -> String? {
    let raw: String? = axAttribute(element, kAXTitleAttribute as String)
    let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
}

func role(of element: AXUIElement) -> String? {
    axAttribute(element, kAXRoleAttribute as String)
}

func subrole(of element: AXUIElement) -> String? {
    axAttribute(element, kAXSubroleAttribute as String)
}

func descriptionText(of element: AXUIElement) -> String {
    let raw: String? = axAttribute(element, kAXDescriptionAttribute as String)
    return raw ?? ""
}

func children(of element: AXUIElement) -> [AXUIElement] {
    let raw: [AXUIElement]? = axAttribute(element, kAXChildrenAttribute as String)
    return raw ?? []
}

func isKeyboardLayoutOverlayWindow(_ element: AXUIElement) -> Bool {
    guard title(of: element) == nil else { return false }
    let elementChildren = children(of: element)
    guard elementChildren.count == 1 else { return false }
    let child = elementChildren[0]
    guard role(of: child) == kAXButtonRole as String else { return false }
    return descriptionText(of: child).hasPrefix("com.apple.keylayout.")
}

func isBlockingDialogWindow(_ element: AXUIElement) -> Bool {
    guard let windowSubrole = subrole(of: element) else { return false }
    guard windowSubrole == kAXDialogSubrole as String || windowSubrole == kAXSystemDialogSubrole as String else {
        return false
    }
    return !isKeyboardLayoutOverlayWindow(element)
}

let logicProKnownBundleIDs = ["com.apple.logic10", "com.apple.mobilelogic"]

func resolveLogicApp() -> NSRunningApplication? {
    let env = ProcessInfo.processInfo.environment
    if let forced = env["LOGIC_PRO_BUNDLE_ID"]?.trimmingCharacters(in: .whitespacesAndNewlines), !forced.isEmpty {
        return NSRunningApplication.runningApplications(withBundleIdentifier: forced).first
    }
    if let frontmostID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
       logicProKnownBundleIDs.contains(frontmostID),
       let app = NSRunningApplication.runningApplications(withBundleIdentifier: frontmostID).first {
        return app
    }
    for bundleID in logicProKnownBundleIDs {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            return app
        }
    }
    return nil
}

let frontmost = NSWorkspace.shared.frontmostApplication
let logicApp = resolveLogicApp()

var error: String?
var windowNames: [String] = []
var menuItems: [String] = []
var blockingDialogPresent = false

if !AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": false] as CFDictionary) {
    error = "accessibility_not_trusted"
} else if let logicApp {
    let appElement = AXUIElementCreateApplication(logicApp.processIdentifier)
    AXUIElementSetMessagingTimeout(appElement, 2.5)

    if let windows: [AXUIElement] = axAttribute(appElement, kAXWindowsAttribute as String) {
        windowNames = windows.compactMap(title)
        blockingDialogPresent = windows.contains(where: isBlockingDialogWindow)
    }

    if let menuBar: AXUIElement = axAttribute(appElement, kAXMenuBarAttribute as String) {
        menuItems = children(of: menuBar).compactMap(title)
    } else {
        error = "logic_menu_bar_unavailable"
    }
} else {
    error = "logic_not_running"
}

let snapshot = Snapshot(
    frontmost_app: frontmost?.localizedName,
    frontmost_bundle_id: frontmost?.bundleIdentifier,
    logic_window_names: windowNames,
    logic_menu_items: menuItems,
    blocking_dialog_present: blockingDialogPresent,
    error: error
)

let data = try JSONEncoder().encode(snapshot)
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data([0x0A]))

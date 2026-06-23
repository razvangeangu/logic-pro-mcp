#!/usr/bin/env swift
import AppKit
import ApplicationServices
import Foundation

struct Snapshot: Encodable {
    let frontmost_app: String?
    let frontmost_bundle_id: String?
    let logic_window_names: [String]
    let logic_menu_items: [String]
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

func children(of element: AXUIElement) -> [AXUIElement] {
    let raw: [AXUIElement]? = axAttribute(element, kAXChildrenAttribute as String)
    return raw ?? []
}

let frontmost = NSWorkspace.shared.frontmostApplication
let logicApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.logic10").first

var error: String?
var windowNames: [String] = []
var menuItems: [String] = []

if !AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": false] as CFDictionary) {
    error = "accessibility_not_trusted"
} else if let logicApp {
    let appElement = AXUIElementCreateApplication(logicApp.processIdentifier)
    AXUIElementSetMessagingTimeout(appElement, 2.5)

    if let windows: [AXUIElement] = axAttribute(appElement, kAXWindowsAttribute as String) {
        windowNames = windows.compactMap(title)
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
    error: error
)

let data = try JSONEncoder().encode(snapshot)
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data([0x0A]))

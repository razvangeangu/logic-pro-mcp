#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

let keyName = CommandLine.arguments.dropFirst().first ?? ""
let keyCodeByName: [String: CGKeyCode] = [
    "space": 49,
    "return": 36,
]

guard let keyCode = keyCodeByName[keyName] else {
    FileHandle.standardError.write(Data("unknown_key\n".utf8))
    exit(64)
}

guard CGPreflightPostEventAccess() else {
    FileHandle.standardError.write(Data("post_event_access_denied\n".utf8))
    exit(2)
}

if let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.logic10").first {
    app.activate()
    usleep(120_000)
}

let source = CGEventSource(stateID: .hidSystemState)
guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
      let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
    FileHandle.standardError.write(Data("event_create_failed\n".utf8))
    exit(1)
}

keyDown.post(tap: .cghidEventTap)
usleep(30_000)
keyUp.post(tap: .cghidEventTap)
print("ok")

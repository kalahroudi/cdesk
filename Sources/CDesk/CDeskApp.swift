// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 kalahroudi

import SwiftUI
import AppKit
import ColimaKit

@main
struct CDeskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() {
        // Command line helpers used by the build scripts and the updater.
        let args = CommandLine.arguments
        if args.contains("--self-test") { print("ok \(BuildInfo.current.commit ?? "dev")"); exit(0) }
        if let i = args.firstIndex(of: "--write-iconset"), i + 1 < args.count {
            do { try AppIcon.writeIconset(to: args[i + 1]); exit(0) } catch { FileHandle.standardError.write(Data("\(error)\n".utf8)); exit(1) }
        }
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count { SnapshotMode.dir = args[i + 1] }

        // Only one copy may run: two would poll the same VM and fight over the menu bar item.
        // Leave before any app state exists, and ask the running copy to show its window.
        if SnapshotMode.dir == nil, let other = Self.otherRunningInstance() {
            if let url = other.bundleURL { NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) } else { other.activate() }
            Thread.sleep(forTimeInterval: 0.3)
            exit(0)
        }
    }

    /// Another live copy of this app. Waits a moment, since an update relaunch starts the new copy as the old one exits.
    private static func otherRunningInstance() -> NSRunningApplication? {
        guard let id = Bundle.main.bundleIdentifier else { return nil }   // a bare `swift run` binary has no identity
        for attempt in 0..<10 {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: id)
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated }
            guard let first = others.first else { return nil }
            if attempt == 9 { return first }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return nil
    }

    var body: some Scene {
        // The real windows are AppKit-managed (see AppDelegate) so they can be freed when closed.
        Settings { EmptyView() }
    }
}

// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 kalahroudi

import SwiftUI
import AppKit
import ColimaKit

/// Owns the menu bar item (with its popover arrow), the Dock presence, and the Manager window.
/// The window is created on demand and destroyed on close, so a closed Manager holds no view memory.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSPopoverDelegate {
    static var shared: AppDelegate { NSApp.delegate as! AppDelegate }
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var managerWindow: NSWindow?
    private let model = AppModel.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        if SnapshotMode.dir != nil { SnapshotMode.run(); return }
        Prefs.shared.applyTheme()
        Prefs.shared.applyDockIcon()
        NSApp.applicationIconImage = AppIcon.image(size: 512, padded: true)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = StatusIcon.image(.stopped)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.setAccessibilityLabel("Colima")

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        model.onStatusChange = { [weak self] running in
            guard let self else { return }
            self.statusItem.button?.image = StatusIcon.image(self.model.busy ? .busy : running == true ? .running : .stopped)
        }

        Task {
            await model.refresh()
            if Prefs.shared.autoStartColima, Colima.isInstalled, model.profile?.isRunning == false, model.profiles.count > 0 { model.startColima() }
        }
        Updater.shared.confirmLaunch()
        Task { Updater.shared.autoCheckIfDue(enabled: Prefs.shared.autoCheckUpdates) }
    }

    @objc func openSettings() { showManager(section: .settings) }

    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = statusItem.button else { return }
        let host = NSHostingController(rootView: PopoverView(openManager: { [weak self] s in self?.showManager(section: s) }))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    func popoverDidClose(_ notification: Notification) {
        popover.contentViewController = nil   // release the popover's views while hidden
    }

    func showManager(section: Section? = nil) {
        if let section { Nav.shared.section = section }
        popover.performClose(nil)
        if managerWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 740),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 900, height: 600)
            w.setFrameAutosaveName("CDeskManager")
            w.delegate = self
            w.contentView = NSHostingView(rootView: ManagerView())
            if !w.setFrameUsingName("CDeskManager") { w.center() }
            managerWindow = w
        }
        managerWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        model.setManagerVisible(true)
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === managerWindow else { return }
        model.setManagerVisible(false)
        managerWindow?.contentView = nil
        managerWindow = nil
    }

    // Clicking the Dock icon opens the Manager.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showManager(); return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        guard Prefs.shared.stopOnQuit, let colima = Shell.find("colima") else { return }
        let p = Process(); p.executableURL = URL(fileURLWithPath: colima)
        p.arguments = ["stop"] + (model.selected == "default" ? [] : [model.selected])
        try? p.run(); p.waitUntilExit()
    }
}

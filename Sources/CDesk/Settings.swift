// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 kalahroudi

import SwiftUI
import ServiceManagement
import AppKit

enum ThemeChoice: String, CaseIterable { case system, light, dark
    var label: String { rawValue.capitalized }
}
/// Terminal apps cdesk can hand a shell to. Only the ones installed on this Mac are offered.
enum TerminalApp: String, CaseIterable, Identifiable {
    case terminal = "Terminal", iterm = "iTerm2", ghostty = "Ghostty", alacritty = "Alacritty", kitty = "kitty", wezterm = "WezTerm"
    var id: String { rawValue }

    var bundleID: String {
        switch self {
        case .terminal: "com.apple.Terminal"
        case .iterm: "com.googlecode.iterm2"
        case .ghostty: "com.mitchellh.ghostty"
        case .alacritty: "org.alacritty"
        case .kitty: "net.kovidgoyal.kitty"
        case .wezterm: "com.github.wez.wezterm"
        }
    }
    var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }
    var isInstalled: Bool { self == .terminal || appURL != nil }
    static var installed: [TerminalApp] { allCases.filter(\.isInstalled) }
}
enum UpdateChannel: String, CaseIterable { case releases, main
    var label: String { self == .releases ? "Releases" : "Main branch" }
}
enum ShellChoice: String, CaseIterable { case bash, sh, zsh }

/// User preferences, stored in UserDefaults.
@MainActor @Observable
final class Prefs {
    static let shared = Prefs()
    private let d = UserDefaults.standard

    var theme: ThemeChoice { didSet { d.set(theme.rawValue, forKey: "theme"); applyTheme() } }
    var terminal: TerminalApp { didSet { d.set(terminal.rawValue, forKey: "terminal") } }
    var shell: ShellChoice { didSet { d.set(shell.rawValue, forKey: "shell") } }
    var autoStartColima: Bool { didSet { d.set(autoStartColima, forKey: "autoStartColima") } }
    var stopOnQuit: Bool { didSet { d.set(stopOnQuit, forKey: "stopOnQuit") } }
    var switchDockerContext: Bool { didSet { d.set(switchDockerContext, forKey: "switchDockerContext") } }
    var notify: Bool { didSet { d.set(notify, forKey: "notify") } }
    var refreshSeconds: Int { didSet { d.set(refreshSeconds, forKey: "refreshSeconds") } }
    var showDockIcon: Bool { didSet { d.set(showDockIcon, forKey: "showDockIcon"); applyDockIcon() } }
    var updateChannel: UpdateChannel { didSet { d.set(updateChannel.rawValue, forKey: "updateChannel") } }
    var autoCheckUpdates: Bool { didSet { d.set(autoCheckUpdates, forKey: "autoCheckUpdates") } }
    var sidebarCollapsed: Bool { didSet { d.set(sidebarCollapsed, forKey: "sidebarCollapsed") } }

    /// Launch at login is on by default; the user can turn it off here. Backed by SMAppService (Login Items).
    private(set) var launchAtLogin: Bool = false
    private(set) var launchAtLoginError: String?

    private init() {
        d.register(defaults: ["autoStartColima": true, "switchDockerContext": true, "notify": true, "refreshSeconds": 5, "showDockIcon": true, "autoCheckUpdates": true, "shell": "bash", "launchAtLoginDefaulted": false])
        theme = ThemeChoice(rawValue: d.string(forKey: "theme") ?? "") ?? .system
        let chosen = TerminalApp(rawValue: d.string(forKey: "terminal") ?? "") ?? .terminal
        terminal = chosen.isInstalled ? chosen : .terminal
        shell = ShellChoice(rawValue: d.string(forKey: "shell") ?? "") ?? .bash
        autoStartColima = d.bool(forKey: "autoStartColima")
        stopOnQuit = d.bool(forKey: "stopOnQuit")
        switchDockerContext = d.bool(forKey: "switchDockerContext")
        notify = d.bool(forKey: "notify")
        refreshSeconds = d.integer(forKey: "refreshSeconds")
        showDockIcon = d.bool(forKey: "showDockIcon")
        sidebarCollapsed = d.bool(forKey: "sidebarCollapsed")
        autoCheckUpdates = d.bool(forKey: "autoCheckUpdates")
        updateChannel = UpdateChannel(rawValue: d.string(forKey: "updateChannel") ?? "") ?? .releases
        // First run: opt in to launch at login. After that the user's choice always wins.
        if !d.bool(forKey: "launchAtLoginDefaulted") {
            d.set(true, forKey: "launchAtLoginDefaulted")
            setLaunchAtLogin(true)
        }
        refreshLaunchAtLogin()
    }

    func refreshLaunchAtLogin() { launchAtLogin = SMAppService.mainApp.status == .enabled }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = "Could not change Login Items: \(error.localizedDescription)"
        }
        refreshLaunchAtLogin()
    }

    func applyTheme() {
        NSApp?.appearance = switch theme { case .system: nil; case .light: NSAppearance(named: .aqua); case .dark: NSAppearance(named: .darkAqua) }
        (NSApp?.delegate as? AppDelegate)?.applyAppearance()
    }

    func applyDockIcon() {
        NSApp?.setActivationPolicy(showDockIcon ? .regular : .accessory)
    }
}

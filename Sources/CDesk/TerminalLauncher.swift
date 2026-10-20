// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 kalahroudi

import Foundation
import AppKit
import ColimaKit

/// Opens commands in the user's terminal app. cdesk does not embed a terminal: handing off keeps the app light
/// and gives you your own shell setup.
enum TerminalLauncher {
    /// Runs `command` in the chosen terminal. With `keepOpen` the window waits for Return at the end, for
    /// one-off tasks whose output you want to read (some terminals close the window when the command exits).
    @MainActor
    static func run(_ command: String, keepOpen: Bool = false) {
        let full = keepOpen ? "\(command); echo; echo 'Finished. Press Return to close.'; read _" : command
        let app = Prefs.shared.terminal.isInstalled ? Prefs.shared.terminal : .terminal
        switch app {
        case .terminal:
            runAppleScript("tell application \"Terminal\"\nactivate\ndo script \"\(escape(full))\"\nend tell")
        case .iterm:
            runAppleScript("tell application \"iTerm\"\nactivate\nset w to (create window with default profile)\ntell current session of w to write text \"\(escape(full))\"\nend tell")
        case .ghostty, .alacritty, .kitty, .wezterm:
            // These take a command on their command line. `open -n` starts a window running it.
            guard let url = app.appURL else { return }
            let tail: [String]
            switch app {
            case .wezterm: tail = ["start", "--", "/bin/sh", "-c", full]
            case .kitty: tail = ["/bin/sh", "-c", full]
            default: tail = ["-e", "/bin/sh", "-c", full]
            }
            Task.detached { _ = try? await Shell.run("open", ["-na", url.path, "--args"] + tail, timeout: 15) }
        }
    }

    private static func escape(_ s: String) -> String { s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }

    private static func runAppleScript(_ script: String) {
        Task.detached { _ = try? await Shell.run("osascript", ["-e", script], timeout: 15) }
    }

    @MainActor
    static func shell(in container: Container, context: String, root: Bool = false) {
        guard let docker = Shell.find("docker") else { return }
        let first = Prefs.shared.shell.rawValue
        let user = root ? "-u 0 " : ""
        // Try the preferred shell, fall back to sh (alpine images have no bash).
        let inner = "command -v \(first) >/dev/null 2>&1 && exec \(first) || exec sh"
        run("\(docker) --context \(context) exec -it \(user)\(container.id) sh -c '\(inner)'")
    }

    @MainActor
    static func logs(of container: Container, context: String) {
        guard let docker = Shell.find("docker") else { return }
        run("\(docker) --context \(context) logs -f --tail 200 \(container.id)")
    }

    @MainActor
    static func sshIntoVM(profile: String) {
        guard let colima = Shell.find("colima") else { return }
        run("\(colima) ssh --profile \(profile)")
    }
}

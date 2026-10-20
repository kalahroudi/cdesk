// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 kalahroudi

import Foundation
import AppKit
import ColimaKit

/// Opens commands in the user's terminal app. cdesk does not embed a terminal: handing off keeps the app light
/// and gives you your own shell setup.
enum TerminalLauncher {
    @MainActor
    static func run(_ command: String) {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script: String
        switch Prefs.shared.terminal {
        case .terminal:
            script = "tell application \"Terminal\"\nactivate\ndo script \"\(escaped)\"\nend tell"
        case .iterm:
            script = "tell application \"iTerm\"\nactivate\nset w to (create window with default profile)\ntell current session of w to write text \"\(escaped)\"\nend tell"
        }
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

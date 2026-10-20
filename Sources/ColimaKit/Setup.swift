// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 kalahroudi

import Foundation

/// First-run detection and installation of what CDesk drives: Homebrew, Colima and the Docker CLI.
public struct SetupState: Equatable, Sendable {
    public var homebrew: Bool
    public var colima: Bool
    public var docker: Bool
    public init(homebrew: Bool, colima: Bool, docker: Bool) { self.homebrew = homebrew; self.colima = colima; self.docker = docker }

    public static func detect() -> SetupState {
        SetupState(homebrew: Shell.find("brew") != nil, colima: Shell.find("colima") != nil, docker: Shell.find("docker") != nil)
    }

    /// Homebrew formulae that are still missing, in install order.
    public var missingPackages: [String] { (colima ? [] : ["colima"]) + (docker ? [] : ["docker"]) }
    public var toolsReady: Bool { missingPackages.isEmpty }
    /// Can CDesk install the missing tools by itself? It needs Homebrew.
    public var canAutoInstall: Bool { homebrew && !toolsReady }

    /// The official Homebrew installer. It asks for your password, so it is run in a terminal, never silently.
    public static let homebrewInstallCommand = "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""

    public var manualCommand: String { "brew install " + missingPackages.joined(separator: " ") }

    /// Runs `brew install` for the missing packages and streams its output.
    public static func installMissing(_ packages: [String], onLine: @escaping @Sendable (String) -> Void) async throws {
        guard !packages.isEmpty else { return }
        let env = ["HOMEBREW_NO_ENV_HINTS": "1", "HOMEBREW_NO_INSTALL_CLEANUP": "1", "HOMEBREW_NO_ANALYTICS": "1"]
        let status = try await Shell.stream("brew", ["install"] + packages, env: env, onLine: onLine)
        if status != 0 { throw ShellError.failed(command: "brew install", status: status, stderr: "brew install \(packages.joined(separator: " ")) failed. See the log for details.") }
    }
}

extension ColimaConfig {
    /// A good first profile for this Mac: a starting size from the hardware, vz and virtiofs, fixed DNS, file-change events.
    public static func recommended(for hw: Hardware) -> ColimaConfig {
        let rec = Recommendation.forHardware(hw)
        var c = ColimaConfig()
        c.cpus = rec.cpus; c.memoryGiB = rec.memoryGiB; c.diskGiB = rec.diskGiB
        c.arch = hw.isAppleSilicon ? "aarch64" : "x86_64"
        c.vmType = .vz; c.mountType = .virtiofs
        c.mountInotify = true
        c.dns = ["1.1.1.1", "8.8.8.8"]
        return c
    }
}

// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 kalahroudi

import Foundation

/// Drives the `colima` CLI.
public struct Colima: Sendable {
    public init() {}

    public static var isInstalled: Bool { Shell.find("colima") != nil }
    public static var dockerInstalled: Bool { Shell.find("docker") != nil }

    public func version() async -> String? {
        guard let out = try? await Shell.check("colima", ["version"], timeout: 10) else { return nil }
        return out.split(separator: "\n").first.map(String.init)
    }

    /// `colima list --json` prints one JSON object per line, one per profile.
    public func profiles() async throws -> [Profile] {
        let out = try await Shell.check("colima", ["list", "--json"], timeout: 15)
        return Self.parseProfiles(out)
    }

    public static func parseProfiles(_ text: String) -> [Profile] {
        struct DTO: Decodable { let name: String; let status: String; let arch: String?; let cpus: Int?; let memory: Int64?; let disk: Int64?; let runtime: String?; let address: String? }
        return text.split(separator: "\n").compactMap { line in
            guard let d = try? JSONDecoder().decode(DTO.self, from: Data(line.utf8)) else { return nil }
            return Profile(name: d.name, status: d.status, arch: d.arch ?? "", cpus: d.cpus ?? 0, memory: d.memory ?? 0, disk: d.disk ?? 0, runtime: d.runtime ?? "docker", address: d.address?.isEmpty == true ? nil : d.address)
        }
    }

    static func profileArgs(_ profile: String) -> [String] { profile == "default" ? [] : [profile] }

    /// Start (or create) a profile. Streams colima's progress output.
    public func start(profile: String, config: ColimaConfig, onLine: @escaping @Sendable (String) -> Void) async throws {
        let args = ["start"] + Self.profileArgs(profile) + config.startArguments()
        let status = try await Shell.stream("colima", args, onLine: onLine)
        if status != 0 { throw ShellError.failed(command: "colima start", status: status, stderr: "colima start failed. See the log above.") }
    }

    /// Start an existing profile using the settings already saved in its colima.yaml.
    public func startExisting(profile: String, onLine: @escaping @Sendable (String) -> Void) async throws {
        let status = try await Shell.stream("colima", ["start"] + Self.profileArgs(profile), onLine: onLine)
        if status != 0 { throw ShellError.failed(command: "colima start", status: status, stderr: "colima start failed. See the log above.") }
    }

    public func stop(profile: String, force: Bool = false, onLine: @escaping @Sendable (String) -> Void) async throws {
        let args = ["stop"] + (force ? ["--force"] : []) + Self.profileArgs(profile)
        let status = try await Shell.stream("colima", args, onLine: onLine)
        if status != 0 { throw ShellError.failed(command: "colima stop", status: status, stderr: "colima stop failed. See the log above.") }
    }

    public func restart(profile: String, onLine: @escaping @Sendable (String) -> Void) async throws {
        let status = try await Shell.stream("colima", ["restart"] + Self.profileArgs(profile), onLine: onLine)
        if status != 0 { throw ShellError.failed(command: "colima restart", status: status, stderr: "colima restart failed. See the log above.") }
    }

    /// Deletes the VM and everything inside it (containers, images, volumes).
    public func delete(profile: String, onLine: @escaping @Sendable (String) -> Void) async throws {
        let status = try await Shell.stream("colima", ["delete", "--force"] + Self.profileArgs(profile), onLine: onLine)
        if status != 0 { throw ShellError.failed(command: "colima delete", status: status, stderr: "colima delete failed. See the log above.") }
    }

    /// Delete and start again with new settings. Needed to change vm-type, mount-type, arch or runtime.
    public func recreate(profile: String, config: ColimaConfig, onLine: @escaping @Sendable (String) -> Void) async throws {
        _ = try? await Shell.stream("colima", ["stop", "--force"] + Self.profileArgs(profile), onLine: onLine)
        try await delete(profile: profile, onLine: onLine)
        try await start(profile: profile, config: config, onLine: onLine)
    }

    /// Re-registers the docker context after a colima update by starting the profile again.
    public func useDockerContext(_ profile: Profile) async throws {
        try await Shell.check("docker", ["context", "use", profile.dockerContext], timeout: 10)
    }
}

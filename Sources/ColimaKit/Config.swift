// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 kalahroudi

import Foundation

public enum VMType: String, CaseIterable, Sendable, Codable { case qemu, vz, krunkit }
public enum MountType: String, CaseIterable, Sendable, Codable { case sshfs, ninep = "9p", virtiofs }
public enum RuntimeKind: String, CaseIterable, Sendable, Codable { case docker, containerd, incus }

/// The `colima start` options cdesk manages. Settings that colima fixes at VM creation are listed in `ColimaConfig.immutableFields`.
public struct ColimaConfig: Equatable, Sendable, Codable {
    public var cpus: Int = 2
    public var memoryGiB: Double = 2
    public var diskGiB: Int = 100
    public var vmType: VMType = .vz
    public var mountType: MountType = .virtiofs
    public var rosetta: Bool = false
    public var arch: String = "aarch64"
    public var runtime: RuntimeKind = .docker
    public var mountInotify: Bool = false
    public var dns: [String] = []
    public var networkAddress: Bool = false
    public var kubernetes: Bool = false
    public var sshAgent: Bool = false
    public var nestedVirtualization: Bool = false
    public var hostname: String = ""

    public init() {}

    /// Fields that cannot change on an existing VM; changing them means delete + recreate.
    public enum Field: String, CaseIterable, Sendable { case vmType, mountType, arch, runtime }
    public static let immutableFields: Set<Field> = [.vmType, .mountType, .arch, .runtime]

    /// Which immutable fields differ between two configs.
    public func recreateReasons(comparedTo old: ColimaConfig) -> [Field] {
        var out: [Field] = []
        if vmType != old.vmType { out.append(.vmType) }
        if mountType != old.mountType { out.append(.mountType) }
        if arch != old.arch { out.append(.arch) }
        if runtime != old.runtime { out.append(.runtime) }
        return out
    }

    public func differsRestartably(from old: ColimaConfig) -> Bool {
        cpus != old.cpus || memoryGiB != old.memoryGiB || diskGiB != old.diskGiB || rosetta != old.rosetta
            || mountInotify != old.mountInotify || dns != old.dns || networkAddress != old.networkAddress
            || kubernetes != old.kubernetes || sshAgent != old.sshAgent || nestedVirtualization != old.nestedVirtualization
            || hostname != old.hostname
    }

    /// Arguments for `colima start` (without the profile or the leading "start").
    public func startArguments() -> [String] {
        var a = ["--cpus", String(cpus), "--memory", Self.formatNumber(memoryGiB), "--disk", String(diskGiB),
                 "--vm-type", vmType.rawValue, "--mount-type", mountType.rawValue,
                 "--arch", arch, "--runtime", runtime.rawValue]
        // Rosetta only exists with the vz VM type.
        if rosetta && vmType == .vz { a.append("--vz-rosetta") }
        if mountInotify { a.append("--mount-inotify") }
        for d in dns { a += ["--dns", d] }
        if networkAddress { a.append("--network-address") }
        if kubernetes { a.append("--kubernetes") }
        if sshAgent { a.append("--ssh-agent") }
        if nestedVirtualization { a.append("--nested-virtualization") }
        if !hostname.isEmpty { a += ["--hostname", hostname] }
        return a
    }

    /// The command as you would type it, for display and copying.
    public func commandLine(profile: String = "default") -> String {
        var parts = ["colima", "start"]
        if profile != "default" { parts.append(profile) }
        return (parts + startArguments()).joined(separator: " ")
    }

    static func formatNumber(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(v)
    }

    // MARK: YAML

    public static func configURL(profile: String) -> URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".colima/\(profile)/colima.yaml")
    }

    public static func load(profile: String) -> ColimaConfig? {
        guard let text = try? String(contentsOf: configURL(profile: profile), encoding: .utf8) else { return nil }
        return parse(yaml: text)
    }

    /// Reads the subset of colima.yaml that cdesk manages. Colima writes simple, flat YAML so a tiny parser is enough
    /// and keeps the app free of third-party dependencies.
    public static func parse(yaml: String) -> ColimaConfig {
        var c = ColimaConfig()
        var section: String? = nil
        var listKey: String? = nil
        for raw in yaml.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(raw)
            if let hash = line.firstIndex(of: "#") { line = String(line[..<hash]) }
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let indent = line.prefix { $0 == " " }.count
            let t = line.trimmingCharacters(in: .whitespaces)

            if t.hasPrefix("- ") {
                let item = unquote(String(t.dropFirst(2)))
                if section == "network", listKey == "dns" { c.dns.append(item) }
                continue
            }
            guard let colon = t.firstIndex(of: ":") else { continue }
            let key = String(t[..<colon])
            let value = unquote(String(t[t.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
            if indent == 0 {
                section = value.isEmpty ? key : nil
                listKey = nil
                switch key {
                case "cpu", "cpus": c.cpus = Int(value) ?? c.cpus
                case "memory": c.memoryGiB = Double(value) ?? c.memoryGiB
                case "disk": c.diskGiB = Int(value) ?? c.diskGiB
                case "vmType": c.vmType = VMType(rawValue: value) ?? c.vmType
                case "mountType": c.mountType = MountType(rawValue: value) ?? c.mountType
                case "rosetta": c.rosetta = value == "true"
                case "arch": c.arch = value
                case "runtime": c.runtime = RuntimeKind(rawValue: value) ?? c.runtime
                case "mountInotify": c.mountInotify = value == "true"
                case "forwardAgent": c.sshAgent = value == "true"
                case "nestedVirtualization": c.nestedVirtualization = value == "true"
                case "hostname": c.hostname = value
                default: break
                }
            } else if section == "network" {
                if key == "address" { c.networkAddress = value == "true" }
                if key == "dns" { listKey = value.isEmpty ? "dns" : nil }
            } else if section == "kubernetes", key == "enabled" {
                c.kubernetes = value == "true"
            }
        }
        return c
    }

    private static func unquote(_ s: String) -> String {
        var v = s
        if v.count >= 2, (v.hasPrefix("\"") && v.hasSuffix("\"")) || (v.hasPrefix("'") && v.hasSuffix("'")) { v = String(v.dropFirst().dropLast()) }
        return v == "null" || v == "[]" || v == "{}" ? "" : v
    }
}

// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 kalahroudi

import Foundation

public enum PruneKind: String, CaseIterable, Sendable, Codable {
    case danglingImages = "dangling-images"
    case unusedImages = "unused-images"
    case stoppedContainers = "stopped-containers"
    case unusedVolumes = "unused-volumes"
    case buildCache = "build-cache"

    var args: [String] {
        switch self {
        case .danglingImages: return ["image", "prune", "--force"]
        case .unusedImages: return ["image", "prune", "--all", "--force"]
        case .stoppedContainers: return ["container", "prune", "--force"]
        case .unusedVolumes: return ["volume", "prune", "--force"]
        case .buildCache: return ["builder", "prune", "--force"]
        }
    }
}

public enum ContainerAction: String, CaseIterable, Sendable, Codable { case start, stop, restart, kill, pause, unpause }

/// Talks to the Docker CLI against one Colima profile (via its docker context), so it never depends on which context is "current".
public struct Docker: Sendable {
    public let context: String
    public init(profile: String = "default") { context = profile == "default" ? "colima" : "colima-\(profile)" }
    public init(context: String) { self.context = context }

    public func run(_ args: [String], timeout: TimeInterval? = 60) async throws -> String {
        try await Shell.check("docker", ["--context", context] + args, timeout: timeout)
    }

    // MARK: Containers

    public func containers() async throws -> [Container] {
        Self.parseContainers(try await run(["ps", "--all", "--format", "{{json .}}"]))
    }

    public static func parseContainers(_ text: String) -> [Container] {
        struct DTO: Decodable { let ID: String; let Names: String; let Image: String; let State: String; let Status: String; let Ports: String?; let Labels: String?; let RunningFor: String? }
        return text.split(separator: "\n").compactMap { line in
            guard let d = try? JSONDecoder().decode(DTO.self, from: Data(line.utf8)) else { return nil }
            let labels = parseLabels(d.Labels ?? "")
            return Container(id: d.ID, name: d.Names, image: d.Image, state: d.State, status: d.Status,
                             ports: simplifyPorts(d.Ports ?? ""), created: d.RunningFor ?? "",
                             project: labels["com.docker.compose.project"], service: labels["com.docker.compose.service"],
                             composeFile: labels["com.docker.compose.project.config_files"])
        }
    }

    /// Docker prints labels as "a=b,c=d". Values may contain commas, so a piece without "=" belongs to the previous value.
    public static func parseLabels(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        var lastKey: String?
        for piece in text.split(separator: ",", omittingEmptySubsequences: true) {
            if let eq = piece.firstIndex(of: "="), !piece[..<eq].contains(" ") {
                let k = String(piece[..<eq]); out[k] = String(piece[piece.index(after: eq)...]); lastKey = k
            } else if let k = lastKey { out[k, default: ""] += "," + piece }
        }
        return out
    }

    /// "0.0.0.0:3000->3000/tcp, :::3000->3000/tcp" becomes "3000→3000".
    public static func simplifyPorts(_ text: String) -> String {
        var seen: [String] = []
        for p in text.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where !p.hasPrefix(":::") && !p.hasPrefix("[::]") {
            let s = p.replacingOccurrences(of: "0.0.0.0:", with: "").replacingOccurrences(of: "/tcp", with: "").replacingOccurrences(of: "->", with: "→")
            if !seen.contains(s) { seen.append(s) }
        }
        return seen.joined(separator: ", ")
    }

    public static func stacks(from containers: [Container]) -> [Stack] {
        Dictionary(grouping: containers.filter { $0.project != nil }, by: { $0.project! })
            .map { name, list in Stack(name: name, containers: list.sorted { $0.name < $1.name }, composeFile: list.compactMap(\.composeFile).first) }
            .sorted { $0.name < $1.name }
    }

    public func stats() async throws -> [ContainerStats] {
        let out = try await run(["stats", "--no-stream", "--format", "{{json .}}"], timeout: 20)
        return Self.parseStats(out)
    }

    public static func parseStats(_ text: String) -> [ContainerStats] {
        struct DTO: Decodable { let ID: String; let CPUPerc: String; let MemUsage: String }
        return text.split(separator: "\n").compactMap { line in
            guard let d = try? JSONDecoder().decode(DTO.self, from: Data(line.utf8)) else { return nil }
            let parts = d.MemUsage.components(separatedBy: " / ")
            return ContainerStats(id: d.ID, cpuPercent: Double(d.CPUPerc.dropLast()) ?? 0,
                                  memoryBytes: parseBinarySize(parts.first ?? ""), memoryLimitBytes: parseBinarySize(parts.count > 1 ? parts[1] : ""))
        }
    }

    /// docker stats uses binary units ("26.3MiB").
    public static func parseBinarySize(_ t: String) -> Int64 {
        let units: [(String, Double)] = [("TiB", 1_099_511_627_776), ("GiB", 1_073_741_824), ("MiB", 1_048_576), ("KiB", 1024), ("kB", 1e3), ("B", 1)]
        for (u, m) in units where t.hasSuffix(u) { if let v = Double(t.dropLast(u.count)) { return Int64(v * m) } }
        return 0
    }

    public func perform(_ action: ContainerAction, ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        try await run([action.rawValue] + ids, timeout: 120)
    }

    public func remove(ids: [String], force: Bool = false) async throws {
        guard !ids.isEmpty else { return }
        try await run(["rm"] + (force ? ["--force"] : []) + ids, timeout: 120)
    }

    public func logs(id: String, tail: Int = 200) async throws -> String {
        let r = try await Shell.run("docker", ["--context", context, "logs", "--tail", String(tail), "--timestamps", id], timeout: 20)
        return r.stdout + r.stderr   // containers write logs to both streams
    }

    /// Non-interactive command inside a container (used by the MCP server).
    public func exec(id: String, command: [String]) async throws -> ShellResult {
        try await Shell.run("docker", ["--context", context, "exec", id] + command, timeout: 60)
    }

    // MARK: Images, volumes, disk

    public func inventory() async throws -> DockerInventory {
        let df = try await run(["system", "df", "--format", "{{json .}}"], timeout: 30)
        let usage = Self.parseUsage(df)
        let verbose = try await run(["system", "df", "-v", "--format", "json"], timeout: 60)
        let (images, volumes) = Self.parseVerboseDf(verbose)
        return DockerInventory(images: images, volumes: volumes, usage: usage)
    }

    public static func parseUsage(_ text: String) -> [DiskUsageRow] {
        struct DTO: Decodable {
            let kind: String; let TotalCount: String; let Active: String; let Size: String; let Reclaimable: String
            enum CodingKeys: String, CodingKey { case kind = "Type", TotalCount, Active, Size, Reclaimable }
        }
        return text.split(separator: "\n").compactMap { line in
            guard let d = try? JSONDecoder().decode(DTO.self, from: Data(line.utf8)) else { return nil }
            return DiskUsageRow(type: d.kind, total: Int(d.TotalCount) ?? 0, active: Int(d.Active) ?? 0, size: d.Size, reclaimable: d.Reclaimable, reclaimableBytes: parseSize(d.Reclaimable))
        }
    }

    public static func parseVerboseDf(_ text: String) -> ([DockerImage], [Volume]) {
        struct Img: Decodable { let ID: String; let Repository: String; let Tag: String; let Size: String; let CreatedSince: String; let Containers: String }
        struct Vol: Decodable { let Name: String; let Driver: String; let Size: String; let Links: String }
        struct Root: Decodable { let Images: [Img]?; let Volumes: [Vol]? }
        guard let root = try? JSONDecoder().decode(Root.self, from: Data(text.utf8)) else { return ([], []) }
        let images = (root.Images ?? []).map { i in
            DockerImage(id: String(i.ID.replacingOccurrences(of: "sha256:", with: "").prefix(12)), repository: i.Repository, tag: i.Tag,
                        size: i.Size, sizeBytes: parseSize(i.Size), created: i.CreatedSince, containers: Int(i.Containers) ?? 0)
        }.sorted { $0.sizeBytes > $1.sizeBytes }
        let volumes = (root.Volumes ?? []).map { Volume(name: $0.Name, driver: $0.Driver, size: $0.Size, sizeBytes: parseSize($0.Size), links: Int($0.Links) ?? 0) }
            .sorted { $0.sizeBytes > $1.sizeBytes }
        return (images, volumes)
    }

    public func pull(image: String, onLine: @escaping @Sendable (String) -> Void) async throws {
        let status = try await Shell.stream("docker", ["--context", context, "pull", image], onLine: onLine)
        if status != 0 { throw ShellError.failed(command: "docker pull \(image)", status: status, stderr: "Could not pull \(image).") }
    }

    public func removeImages(_ refs: [String], force: Bool = false) async throws {
        guard !refs.isEmpty else { return }
        try await run(["rmi"] + (force ? ["--force"] : []) + refs, timeout: 120)
    }

    public func removeVolumes(_ names: [String]) async throws {
        guard !names.isEmpty else { return }
        try await run(["volume", "rm"] + names, timeout: 60)
    }

    public func prune(_ kind: PruneKind) async throws -> String {
        try await run(kind.args, timeout: 300)
    }

    /// True when any local image is linux/amd64 (so Rosetta would help).
    public func hasAmd64Images() async -> Bool {
        guard let ids = try? await run(["images", "--quiet"]), !ids.isEmpty else { return false }
        let list = Array(Set(ids.split(separator: "\n").map(String.init)))
        guard let out = try? await run(["image", "inspect", "--format", "{{.Architecture}}"] + list) else { return false }
        return out.split(separator: "\n").contains("amd64")
    }
}

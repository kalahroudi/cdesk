// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 kalahroudi

import Foundation

public struct Profile: Identifiable, Hashable, Sendable, Codable {
    public let name: String
    public let status: String
    public let arch: String
    public let cpus: Int
    public let memory: Int64   // bytes
    public let disk: Int64     // bytes
    public let runtime: String
    public let address: String?

    public var id: String { name }
    public var isRunning: Bool { status.lowercased() == "running" }
    public var memoryGiB: Double { Double(memory) / 1_073_741_824 }
    public var diskGiB: Double { Double(disk) / 1_073_741_824 }
    /// The docker context colima registers for this profile.
    public var dockerContext: String { name == "default" ? "colima" : "colima-\(name)" }

    public init(name: String, status: String, arch: String, cpus: Int, memory: Int64, disk: Int64, runtime: String, address: String? = nil) {
        self.name = name; self.status = status; self.arch = arch; self.cpus = cpus
        self.memory = memory; self.disk = disk; self.runtime = runtime; self.address = address
    }
}

public struct Container: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let name: String
    public let image: String
    public let state: String       // running, exited, paused, created...
    public let status: String      // "Up 4 days", "Exited (1) 5 days ago"
    public let ports: String
    public let created: String
    public let project: String?    // compose project (the "stack")
    public let service: String?    // compose service name
    public let composeFile: String?

    public var isRunning: Bool { state == "running" }
    public init(id: String, name: String, image: String, state: String, status: String, ports: String, created: String, project: String?, service: String?, composeFile: String? = nil) {
        self.id = id; self.name = name; self.image = image; self.state = state; self.status = status
        self.ports = ports; self.created = created; self.project = project; self.service = service; self.composeFile = composeFile
    }
}

public struct ContainerStats: Hashable, Sendable, Codable {
    public let id: String
    public let cpuPercent: Double
    public let memoryBytes: Int64
    public let memoryLimitBytes: Int64
    public init(id: String, cpuPercent: Double, memoryBytes: Int64, memoryLimitBytes: Int64) {
        self.id = id; self.cpuPercent = cpuPercent; self.memoryBytes = memoryBytes; self.memoryLimitBytes = memoryLimitBytes
    }
}

public struct Stack: Identifiable, Hashable, Sendable {
    public let name: String
    public let containers: [Container]
    public let composeFile: String?
    public var id: String { name }
    public var runningCount: Int { containers.filter(\.isRunning).count }
}

public struct DockerImage: Identifiable, Hashable, Sendable, Codable {
    public let id: String          // short id without sha256:
    public let repository: String
    public let tag: String
    public let size: String
    public let sizeBytes: Int64
    public let created: String
    public let containers: Int

    public var isDangling: Bool { repository == "<none>" }
    public var isUsed: Bool { containers > 0 }
    public var reference: String { isDangling ? id : "\(repository):\(tag)" }
    public init(id: String, repository: String, tag: String, size: String, sizeBytes: Int64, created: String, containers: Int) {
        self.id = id; self.repository = repository; self.tag = tag; self.size = size
        self.sizeBytes = sizeBytes; self.created = created; self.containers = containers
    }
}

public struct Volume: Identifiable, Hashable, Sendable, Codable {
    public let name: String
    public let driver: String
    public let size: String
    public let sizeBytes: Int64
    public let links: Int          // containers using it
    public var id: String { name }
    public var isUsed: Bool { links > 0 }
    public init(name: String, driver: String, size: String, sizeBytes: Int64, links: Int) {
        self.name = name; self.driver = driver; self.size = size; self.sizeBytes = sizeBytes; self.links = links
    }
}

public struct DiskUsageRow: Identifiable, Hashable, Sendable, Codable {
    public let type: String        // Images, Containers, Local Volumes, Build Cache
    public let total: Int
    public let active: Int
    public let size: String
    public let reclaimable: String
    public let reclaimableBytes: Int64
    public var id: String { type }
    public init(type: String, total: Int, active: Int, size: String, reclaimable: String, reclaimableBytes: Int64) {
        self.type = type; self.total = total; self.active = active; self.size = size
        self.reclaimable = reclaimable; self.reclaimableBytes = reclaimableBytes
    }
}

public struct DockerInventory: Sendable {
    public var images: [DockerImage]
    public var volumes: [Volume]
    public var usage: [DiskUsageRow]
    public var reclaimableBytes: Int64 { usage.reduce(0) { $0 + $1.reclaimableBytes } }
}

/// Parses docker's human sizes ("2.71GB", "24.6kB", "292.4MB (85%)") into bytes. Docker uses powers of 1000.
public func parseSize(_ text: String) -> Int64 {
    let t = text.split(separator: " ").first.map(String.init) ?? text
    let units: [(String, Double)] = [("TB", 1e12), ("GB", 1e9), ("MB", 1e6), ("kB", 1e3), ("KB", 1e3), ("B", 1)]
    for (u, m) in units where t.hasSuffix(u) {
        if let v = Double(t.dropLast(u.count)) { return Int64(v * m) }
    }
    return 0
}

public func formatBytes(_ bytes: Int64) -> String {
    let f = ByteCountFormatter()
    f.countStyle = .file
    return f.string(fromByteCount: bytes)
}

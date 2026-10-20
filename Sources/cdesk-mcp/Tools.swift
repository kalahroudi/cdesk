// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 kalahroudi

import Foundation
import ColimaKit

typealias Args = [String: Any]

struct Tool {
    let name: String
    let description: String
    let properties: [String: Any]
    let required: [String]
    let handler: @Sendable (Args) async throws -> String

    var definition: [String: Any] {
        ["name": name, "description": description,
         "inputSchema": ["type": "object", "properties": properties, "required": required] as [String: Any]]
    }
}

final class LineLog: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    func add(_ l: String) { lock.lock(); lines.append(l); lock.unlock() }
    func tail(_ n: Int) -> String { lock.lock(); defer { lock.unlock() }; return lines.suffix(n).joined(separator: "\n") }
}

struct ToolError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private func str(_ d: [String: String]) -> [String: Any] { d }
private func prop(_ type: String, _ desc: String, enumValues: [String]? = nil) -> [String: Any] {
    var p: [String: Any] = ["type": type, "description": desc]
    if let e = enumValues { p["enum"] = e }
    return p
}
private let profileProp = prop("string", "Colima profile name. Defaults to \"default\".")

private func json<T: Encodable>(_ value: T) throws -> String {
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try enc.encode(value), as: UTF8.self)
}

private func profileName(_ a: Args) -> String { (a["profile"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "default" }
private func requireString(_ a: Args, _ key: String) throws -> String {
    guard let v = a[key] as? String, !v.isEmpty else { throw ToolError(message: "Missing required argument: \(key)") }
    return v
}
private func number(_ a: Args, _ key: String) -> Double? { (a[key] as? Double) ?? (a[key] as? Int).map(Double.init) }

private func applyOverrides(_ a: Args, to c: inout ColimaConfig) {
    if let v = number(a, "cpus") { c.cpus = Int(v) }
    if let v = number(a, "memory_gib") { c.memoryGiB = v }
    if let v = number(a, "disk_gib") { c.diskGiB = Int(v) }
    if let v = a["vm_type"] as? String, let t = VMType(rawValue: v) { c.vmType = t }
    if let v = a["mount_type"] as? String, let t = MountType(rawValue: v) { c.mountType = t }
    if let v = a["rosetta"] as? Bool { c.rosetta = v }
    if let v = a["mount_inotify"] as? Bool { c.mountInotify = v }
    if let v = a["dns"] as? [String] { c.dns = v }
}

private let configProps: [String: Any] = [
    "cpus": prop("integer", "Number of CPUs."),
    "memory_gib": prop("number", "Memory in GiB."),
    "disk_gib": prop("integer", "Disk size in GiB (can only grow)."),
    "vm_type": prop("string", "VM type. Fixed at creation.", enumValues: VMType.allCases.map(\.rawValue)),
    "mount_type": prop("string", "Mount type. Fixed at creation.", enumValues: MountType.allCases.map(\.rawValue)),
    "rosetta": prop("boolean", "Use Rosetta for amd64 images (vz only)."),
    "mount_inotify": prop("boolean", "Propagate file-change events into the VM."),
    "dns": ["type": "array", "items": ["type": "string"], "description": "Fixed DNS resolvers, e.g. [\"1.1.1.1\"]."] as [String: Any],
]

let allTools: [Tool] = {
    let colima = Colima()
    var t: [Tool] = []

    t.append(Tool(name: "colima_profiles", description: "List Colima profiles with status, CPUs, memory, disk and runtime.", properties: [:], required: []) { _ in
        try json(try await colima.profiles())
    })

    t.append(Tool(name: "colima_config", description: "Read the saved colima.yaml settings of a profile (cpus, memory, vm type, mount type, dns, ...).", properties: ["profile": profileProp], required: []) { a in
        guard let c = ColimaConfig.load(profile: profileName(a)) else { throw ToolError(message: "No colima.yaml found for profile \(profileName(a)).") }
        return try json(c)
    })

    t.append(Tool(name: "colima_recommend", description: "Recommended CPU/memory/disk for this Mac plus plain-language optimisation advice for a profile (vz, virtiofs, DNS, inotify, Rosetta).", properties: ["profile": profileProp], required: []) { a in
        let hw = Hardware.current()
        let cfg = ColimaConfig.load(profile: profileName(a)) ?? ColimaConfig()
        let rec = Recommendation.forHardware(hw)
        let amd64 = await Docker(profile: profileName(a)).hasAmd64Images()
        struct Out: Encodable { let memoryGiB: Double; let cores: Int; let recommended: [String: Double]; let advice: [[String: String]] }
        let advice = Optimizer.advice(config: cfg, hardware: hw, hasAmd64Images: amd64).map {
            ["id": $0.id, "title": $0.title, "detail": $0.detail, "requires": "\($0.effect)"]
        }
        return try json(Out(memoryGiB: hw.memoryGiB, cores: hw.totalCores, recommended: ["cpus": Double(rec.cpus), "memory_gib": rec.memoryGiB, "disk_gib": Double(rec.diskGiB)], advice: advice))
    })

    t.append(Tool(name: "colima_start", description: "Start a Colima profile. Without overrides it uses the saved settings. Overrides apply only to restartable settings (cpus, memory, disk, rosetta, inotify, dns); use colima_recreate to change vm_type or mount_type.",
                  properties: ["profile": profileProp].merging(configProps) { a, _ in a }, required: []) { a in
        let name = profileName(a)
        let log = LineLog()
        let sink: @Sendable (String) -> Void = { log.add($0) }
        let overrides = a.keys.contains { configProps.keys.contains($0) }
        if overrides {
            var c = ColimaConfig.load(profile: name) ?? ColimaConfig()
            applyOverrides(a, to: &c)
            try await colima.start(profile: name, config: c, onLine: sink)
        } else {
            try await colima.startExisting(profile: name, onLine: sink)
        }
        return "Profile \(name) started.\n" + log.tail(5)
    })

    t.append(Tool(name: "colima_stop", description: "Stop a Colima profile (containers stop too).", properties: ["profile": profileProp, "force": prop("boolean", "Force stop a stuck VM.")], required: []) { a in
        try await colima.stop(profile: profileName(a), force: a["force"] as? Bool ?? false) { _ in }
        return "Profile \(profileName(a)) stopped."
    })

    t.append(Tool(name: "colima_restart", description: "Restart a Colima profile.", properties: ["profile": profileProp], required: []) { a in
        try await colima.restart(profile: profileName(a)) { _ in }
        return "Profile \(profileName(a)) restarted."
    })

    t.append(Tool(name: "colima_recreate", description: "DESTRUCTIVE. Delete the VM (all containers, images and volumes inside it) and create it again with new settings. Required to change vm_type or mount_type. confirm_name must equal the profile name.",
                  properties: ["profile": profileProp, "confirm_name": prop("string", "Must equal the profile name.")].merging(configProps) { a, _ in a }, required: ["confirm_name"]) { a in
        let name = profileName(a)
        guard a["confirm_name"] as? String == name else { throw ToolError(message: "Refusing: confirm_name must exactly equal the profile name \"\(name)\". This deletes all containers, images and volumes in the VM.") }
        var c = ColimaConfig.load(profile: name) ?? ColimaConfig()
        applyOverrides(a, to: &c)
        try await colima.recreate(profile: name, config: c) { _ in }
        return "Profile \(name) recreated with: \(c.commandLine(profile: name))"
    })

    // MARK: docker
    t.append(Tool(name: "docker_containers", description: "List containers (all states) in a profile.", properties: ["profile": profileProp, "running_only": prop("boolean", "Only running containers.")], required: []) { a in
        let all = try await Docker(profile: profileName(a)).containers()
        return try json((a["running_only"] as? Bool ?? false) ? all.filter(\.isRunning) : all)
    })

    t.append(Tool(name: "docker_stats", description: "Live CPU and memory per running container.", properties: ["profile": profileProp], required: []) { a in
        try json(try await Docker(profile: profileName(a)).stats())
    })

    t.append(Tool(name: "docker_stacks", description: "List Compose stacks (projects) with their containers.", properties: ["profile": profileProp], required: []) { a in
        struct S: Encodable { let name: String; let running: Int; let total: Int; let composeFile: String?; let containers: [String] }
        let stacks = Docker.stacks(from: try await Docker(profile: profileName(a)).containers())
        return try json(stacks.map { S(name: $0.name, running: $0.runningCount, total: $0.containers.count, composeFile: $0.composeFile, containers: $0.containers.map(\.name)) })
    })

    t.append(Tool(name: "docker_container_action", description: "Start, stop, restart, kill, pause or unpause a container (id or name).",
                  properties: ["profile": profileProp, "container": prop("string", "Container id or name."), "action": prop("string", "Action.", enumValues: ContainerAction.allCases.map(\.rawValue))], required: ["container", "action"]) { a in
        guard let act = ContainerAction(rawValue: try requireString(a, "action")) else { throw ToolError(message: "Unknown action.") }
        try await Docker(profile: profileName(a)).perform(act, ids: [try requireString(a, "container")])
        return "\(act.rawValue) done."
    })

    t.append(Tool(name: "docker_stack_action", description: "Start, stop or restart every container in a Compose stack.",
                  properties: ["profile": profileProp, "stack": prop("string", "Compose project name."), "action": prop("string", "Action.", enumValues: ["start", "stop", "restart"])], required: ["stack", "action"]) { a in
        let d = Docker(profile: profileName(a))
        let stack = try requireString(a, "stack")
        guard let act = ContainerAction(rawValue: try requireString(a, "action")), [.start, .stop, .restart].contains(act) else { throw ToolError(message: "action must be start, stop or restart.") }
        let ids = Docker.stacks(from: try await d.containers()).first { $0.name == stack }?.containers.map(\.id) ?? []
        guard !ids.isEmpty else { throw ToolError(message: "No stack named \(stack).") }
        try await d.perform(act, ids: ids)
        return "\(act.rawValue) applied to \(ids.count) containers in \(stack)."
    })

    t.append(Tool(name: "docker_container_logs", description: "Recent logs of a container.", properties: ["profile": profileProp, "container": prop("string", "Container id or name."), "tail": prop("integer", "Lines from the end. Default 100.")], required: ["container"]) { a in
        try await Docker(profile: profileName(a)).logs(id: try requireString(a, "container"), tail: Int(number(a, "tail") ?? 100))
    })

    t.append(Tool(name: "docker_exec", description: "Run a non-interactive command inside a running container and return its output.",
                  properties: ["profile": profileProp, "container": prop("string", "Container id or name."), "command": ["type": "array", "items": ["type": "string"], "description": "Command and arguments, e.g. [\"ls\", \"-la\", \"/app\"]."] as [String: Any]], required: ["container", "command"]) { a in
        guard let cmd = a["command"] as? [String], !cmd.isEmpty else { throw ToolError(message: "command must be a non-empty array of strings.") }
        let r = try await Docker(profile: profileName(a)).exec(id: try requireString(a, "container"), command: cmd)
        return "exit \(r.status)\n" + r.stdout + (r.stderr.isEmpty ? "" : "\nstderr:\n" + r.stderr)
    })

    t.append(Tool(name: "docker_remove_container", description: "Remove a container. Use force to remove a running one.", properties: ["profile": profileProp, "container": prop("string", "Container id or name."), "force": prop("boolean", "Force removal.")], required: ["container"]) { a in
        try await Docker(profile: profileName(a)).remove(ids: [try requireString(a, "container")], force: a["force"] as? Bool ?? false)
        return "Removed."
    })

    t.append(Tool(name: "docker_images", description: "List images with size, age and whether a container uses them.", properties: ["profile": profileProp], required: []) { a in
        try json(try await Docker(profile: profileName(a)).inventory().images)
    })

    t.append(Tool(name: "docker_volumes", description: "List volumes with size and whether a container uses them.", properties: ["profile": profileProp], required: []) { a in
        try json(try await Docker(profile: profileName(a)).inventory().volumes)
    })

    t.append(Tool(name: "docker_disk_usage", description: "Disk used by images, containers, volumes and build cache, and how much is reclaimable.", properties: ["profile": profileProp], required: []) { a in
        try json(try await Docker(profile: profileName(a)).inventory().usage)
    })

    t.append(Tool(name: "docker_pull", description: "Pull an image, e.g. postgres:16.", properties: ["profile": profileProp, "image": prop("string", "Image reference.")], required: ["image"]) { a in
        try await Docker(profile: profileName(a)).pull(image: try requireString(a, "image")) { _ in }
        return "Pulled \(try requireString(a, "image"))."
    })

    t.append(Tool(name: "docker_remove_image", description: "Remove an image by reference or id. Fails if a container uses it unless force is set.", properties: ["profile": profileProp, "image": prop("string", "Image reference or id."), "force": prop("boolean", "Force removal.")], required: ["image"]) { a in
        try await Docker(profile: profileName(a)).removeImages([try requireString(a, "image")], force: a["force"] as? Bool ?? false)
        return "Removed."
    })

    t.append(Tool(name: "docker_remove_volume", description: "DESTRUCTIVE. Remove a volume and its data. confirm_name must equal the volume name.", properties: ["profile": profileProp, "volume": prop("string", "Volume name."), "confirm_name": prop("string", "Must equal the volume name.")], required: ["volume", "confirm_name"]) { a in
        let v = try requireString(a, "volume")
        guard a["confirm_name"] as? String == v else { throw ToolError(message: "Refusing: confirm_name must exactly equal the volume name. Volume data cannot be recovered.") }
        try await Docker(profile: profileName(a)).removeVolumes([v])
        return "Removed volume \(v)."
    })

    t.append(Tool(name: "docker_prune", description: "Reclaim disk space. kind: dangling-images, unused-images, stopped-containers, unused-volumes (DESTRUCTIVE), build-cache. confirm must be true.",
                  properties: ["profile": profileProp, "kind": prop("string", "What to prune.", enumValues: PruneKind.allCases.map(\.rawValue)), "confirm": prop("boolean", "Must be true.")], required: ["kind", "confirm"]) { a in
        guard a["confirm"] as? Bool == true else { throw ToolError(message: "Refusing: set confirm to true to prune.") }
        guard let kind = PruneKind(rawValue: try requireString(a, "kind")) else { throw ToolError(message: "Unknown kind.") }
        return try await Docker(profile: profileName(a)).prune(kind)
    })

    return t
}()

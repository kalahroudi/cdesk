// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 kalahroudi

import SwiftUI
import ColimaKit
import UserNotifications

struct BackgroundTask: Identifiable {
    enum State: Equatable { case running, done, failed(String) }
    let id = UUID()
    var title: String
    var state: State = .running
    var lines: [String] = []
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    var isError = false
}

struct Sample { let cpu: Double; let memGiB: Double }

enum SideSheet: Identifiable, Equatable {
    case recreate, pullImage, newProfile, prune(PruneKind), removeContainers([String]), removeImages([String]), removeVolume(String), removeProfile(String)
    var id: String {
        switch self {
        case .recreate: "recreate"; case .pullImage: "pull"; case .newProfile: "newProfile"
        case .prune(let k): "prune-\(k.rawValue)"; case .removeContainers: "rmc"; case .removeImages: "rmi"
        case .removeVolume(let n): "rmv-\(n)"; case .removeProfile(let n): "rmp-\(n)"
        }
    }
}

/// App-wide state. Data is only refreshed while the popover or the manager window is visible, so an idle cdesk costs nothing.
@MainActor @Observable
final class AppModel {
    static let shared = AppModel()
    let colima = Colima()
    var hardware = Hardware.current()

    // Data
    var profiles: [Profile] = []
    var selected = "default"
    var containers: [Container] = []
    var stats: [String: ContainerStats] = [:]
    var inventory: DockerInventory?
    var hasAmd64 = false
    var history: [Sample] = []
    var colimaVersion: String?
    var loadedOnce = false

    // Config being edited vs. what colima has saved
    var saved = ColimaConfig()
    var draft = ColimaConfig()

    // UI state
    var tasks: [BackgroundTask] = []
    var toast: Toast?
    var sheet: SideSheet?
    var missingTool: String?
    var updatedAt: Date?

    var onStatusChange: ((Bool?) -> Void)?
    /// Set by `CDesk --snapshot` so screenshots use sample data and nothing is refreshed.
    var demo = false

    private var pollTask: Task<Void, Never>?
    private var popoverVisible = false
    private var managerVisible = false
    private var inventoryAge = Date.distantPast

    var settings: Prefs { Prefs.shared }
    var docker: Docker { Docker(profile: selected) }
    var profile: Profile? { profiles.first { $0.name == selected } }
    var isRunning: Bool { profile?.isRunning ?? false }
    var stacks: [Stack] { Docker.stacks(from: containers) }
    var recommendation: Recommendation { .forHardware(hardware) }
    var advice: [Advice] {
        Optimizer.advice(config: saved, hardware: hardware, usedMemoryGiB: usedMemoryGiB, hasAmd64Images: hasAmd64)
    }
    var usedMemoryGiB: Double? { stats.isEmpty ? nil : Double(stats.values.reduce(0) { $0 + $1.memoryBytes }) / 1_073_741_824 }
    var totalCPUPercent: Double { stats.values.reduce(0) { $0 + $1.cpuPercent } }
    var busy: Bool { tasks.contains { $0.state == .running } }
    var runningTask: BackgroundTask? { tasks.last { $0.state == .running } }

    var restartPending: Bool { draft.differsRestartably(from: saved) }
    var recreateReasons: [ColimaConfig.Field] { draft.recreateReasons(comparedTo: saved) }
    /// The draft with the settings colima can't change in place held at their saved values.
    var restartOnlyConfig: ColimaConfig {
        var c = draft
        c.vmType = saved.vmType; c.mountType = saved.mountType; c.arch = saved.arch; c.runtime = saved.runtime
        return c
    }
    var hasPendingChanges: Bool { restartPending || !recreateReasons.isEmpty }

    // MARK: Visibility-driven polling

    func setPopoverVisible(_ v: Bool) { popoverVisible = v; updatePolling() }
    func setManagerVisible(_ v: Bool) { managerVisible = v; updatePolling() }

    private func updatePolling() {
        let active = popoverVisible || managerVisible
        if active, pollTask == nil {
            pollTask = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.refresh()
                    let secs = max(2, self?.settings.refreshSeconds ?? 5)
                    try? await Task.sleep(for: .seconds(secs))
                }
            }
        } else if !active {
            pollTask?.cancel(); pollTask = nil
        }
    }

    // MARK: Refresh

    func refresh(forceInventory: Bool = false) async {
        if demo { loadedOnce = true; return }
        guard Colima.isInstalled else { missingTool = "colima"; loadedOnce = true; return }
        guard Colima.dockerInstalled else { missingTool = "docker"; loadedOnce = true; return }
        missingTool = nil
        if colimaVersion == nil { colimaVersion = await colima.version() }
        do {
            let list = try await colima.profiles()
            profiles = list
            if !list.contains(where: { $0.name == selected }), let first = list.first { selected = first.name; loadConfig() }
            if !loadedOnce { loadConfig() }
        } catch { profiles = [] }
        onStatusChange?(profile?.isRunning)

        guard let p = profile, p.isRunning else {
            containers = []; stats = [:]; inventory = nil
            loadedOnce = true; updatedAt = .now
            return
        }
        let d = docker
        async let cs = try? d.containers()
        async let st = try? d.stats()
        let (newContainers, newStats) = await (cs, st)
        if let c = newContainers { containers = c }
        if let s = newStats { stats = Dictionary(uniqueKeysWithValues: s.map { ($0.id, $0) }) }
        history.append(Sample(cpu: totalCPUPercent, memGiB: usedMemoryGiB ?? 0))
        if history.count > 60 { history.removeFirst(history.count - 60) }

        // Inventory (images, volumes, disk) is heavier: only when the manager is open, and not on every tick.
        if managerVisible, forceInventory || Date().timeIntervalSince(inventoryAge) > 20 {
            if let inv = try? await d.inventory() { inventory = inv; inventoryAge = .now }
            hasAmd64 = await d.hasAmd64Images()
        }
        loadedOnce = true
        updatedAt = .now
    }

    func select(profile name: String) {
        selected = name
        containers = []; stats = [:]; inventory = nil; history = []
        loadConfig()
        Task { await refresh(forceInventory: true) }
    }

    func loadConfig() {
        let c = ColimaConfig.load(profile: selected) ?? ColimaConfig()
        saved = c; draft = c
    }

    // MARK: Background tasks (non-blocking)

    func runTask(_ title: String, notifyDone: Bool = true, work: @escaping @Sendable (@escaping @Sendable (String) -> Void) async throws -> Void) {
        var t = BackgroundTask(title: title)
        t.lines = ["Starting…"]
        let id = t.id
        tasks.append(t)
        Task {
            do {
                try await work { line in
                    Task { @MainActor in
                        if let i = AppModel.shared.tasks.firstIndex(where: { $0.id == id }) {
                            AppModel.shared.tasks[i].lines.append(line)
                            if AppModel.shared.tasks[i].lines.count > 200 { AppModel.shared.tasks[i].lines.removeFirst(100) }
                        }
                    }
                }
                finish(id, .done)
                if notifyDone { notify("\(title) finished") }
            } catch {
                finish(id, .failed(error.localizedDescription))
                notify("\(title) failed", body: error.localizedDescription)
            }
            await refresh(forceInventory: true)
            // Drop finished tasks after a while so the list stays small.
            try? await Task.sleep(for: .seconds(20))
            tasks.removeAll { $0.id == id && $0.state != .running }
        }
    }

    private func finish(_ id: UUID, _ state: BackgroundTask.State) {
        if let i = tasks.firstIndex(where: { $0.id == id }) { tasks[i].state = state }
        if case .failed(let m) = state { show(m, error: true) } else if let t = tasks.first(where: { $0.id == id }) { show("\(t.title) finished") }
    }

    func show(_ message: String, error: Bool = false) {
        let t = Toast(message: message, isError: error)
        toast = t
        Task { try? await Task.sleep(for: .seconds(error ? 8 : 3.5)); if toast == t { toast = nil } }
    }

    func notify(_ title: String, body: String = "") {
        guard settings.notify, Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let c = UNMutableNotificationContent(); c.title = title; c.body = body
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
        }
    }

    // MARK: Colima actions

    func startColima() {
        let name = selected, cfg = draft, s = settings.switchDockerContext, cm = colima
        let existing = ColimaConfig.load(profile: name) != nil
        runTask("Starting \(name)") { log in
            if existing { try await cm.startExisting(profile: name, onLine: log) } else { try await cm.start(profile: name, config: cfg, onLine: log) }
            if s { try? await Shell.check("docker", ["context", "use", name == "default" ? "colima" : "colima-\(name)"], timeout: 10) }
        }
    }

    func stopColima(force: Bool = false) {
        let name = selected, cm = colima
        runTask("Stopping \(name)") { log in try await cm.stop(profile: name, force: force, onLine: log) }
    }

    func restartColima() {
        let name = selected, cm = colima
        runTask("Restarting \(name)") { log in try await cm.restart(profile: name, onLine: log) }
    }

    /// Apply settings that colima can change in place: stop, then start with the new flags.
    func applyAndRestart() {
        let name = selected, cfg = restartOnlyConfig, cm = colima, wasRunning = isRunning
        runTask("Applying settings to \(name)") { log in
            if wasRunning { try await cm.stop(profile: name, onLine: log) }
            try await cm.start(profile: name, config: cfg, onLine: log)
        }
        saved = cfg
    }

    struct Backup { var volumes: [String] = []; var files = false }

    /// Delete and rebuild the VM. Backups run first, while the old VM is still there.
    func recreate(config: ColimaConfig, backup: Backup = Backup()) {
        let name = selected, cm = colima, d = docker, images = (inventory?.images ?? []).filter { !$0.isDangling }.map(\.reference)
        runTask("Recreating \(name)") { log in
            if backup.files || !backup.volumes.isEmpty {
                let dir = NSHomeDirectory() + "/Colima Backups/\(name)"
                try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                if backup.files {
                    try? FileManager.default.copyItem(atPath: ColimaConfig.configURL(profile: name).path, toPath: dir + "/colima.yaml")
                    try images.joined(separator: "\n").write(toFile: dir + "/images.txt", atomically: true, encoding: .utf8)
                    log("Saved colima.yaml and image list to \(dir)")
                }
                for v in backup.volumes {
                    log("Exporting volume \(v)…")
                    _ = try await d.run(["run", "--rm", "-v", "\(v):/v:ro", "-v", "\(dir):/backup", "alpine", "tar", "czf", "/backup/\(v).tgz", "-C", "/v", "."], timeout: 600)
                }
            }
            try await cm.recreate(profile: name, config: config, onLine: log)
        }
        saved = config; draft = config
    }

    func createProfile(name: String, config: ColimaConfig) {
        let cm = colima
        runTask("Creating profile \(name)") { log in try await cm.start(profile: name, config: config, onLine: log) }
        selected = name
        saved = config; draft = config
    }

    func deleteProfile(_ name: String) {
        let cm = colima
        runTask("Deleting profile \(name)") { log in
            _ = try? await cm.stop(profile: name, force: true, onLine: log)
            try await cm.delete(profile: name, onLine: log)
        }
    }

    // MARK: Repair (the guide's troubleshooting, one click each)

    /// VM stuck on startup: force stop, then start again with the saved settings.
    func repairForceRestart() {
        let name = selected, cm = colima
        runTask("Force restarting \(name)") { log in
            _ = try? await cm.stop(profile: name, force: true, onLine: log)
            try await cm.startExisting(profile: name, onLine: log)
        }
    }

    /// Docker context disappeared after a Colima update: select it again, or start so Colima registers it.
    func repairDockerContext() {
        let p = profile, name = selected, cm = colima
        runTask("Re-registering Docker context") { log in
            let ctx = p?.dockerContext ?? (name == "default" ? "colima" : "colima-\(name)")
            let r = try await Shell.run("docker", ["context", "use", ctx], timeout: 10)
            if !r.ok { log("Context missing; starting Colima to register it"); try await cm.startExisting(profile: name, onLine: log) }
            else { log("Using docker context \(ctx)") }
        }
    }

    /// Containers can't reach the internet: almost always DNS. Pin resolvers and restart.
    func repairDNS() {
        draft.dns = ["1.1.1.1", "8.8.8.8"]
        applyAndRestart()
    }

    // MARK: Docker actions

    func perform(_ action: ContainerAction, ids: [String]) {
        let d = docker
        Task {
            do { try await d.perform(action, ids: ids) } catch { show(error.localizedDescription, error: true) }
            await refresh()
        }
    }

    func removeContainers(_ ids: [String]) {
        let d = docker
        Task {
            do { try await d.remove(ids: ids, force: true); show("Removed \(ids.count) container\(ids.count == 1 ? "" : "s")") } catch { show(error.localizedDescription, error: true) }
            await refresh(forceInventory: true)
        }
    }

    func removeImages(_ refs: [String]) {
        let d = docker
        Task {
            do { try await d.removeImages(refs); show("Removed \(refs.count) image\(refs.count == 1 ? "" : "s")") } catch { show(error.localizedDescription, error: true) }
            await refresh(forceInventory: true)
        }
    }

    func removeVolume(_ name: String) {
        let d = docker
        Task {
            do { try await d.removeVolumes([name]); show("Removed volume") } catch { show(error.localizedDescription, error: true) }
            await refresh(forceInventory: true)
        }
    }

    func pull(_ image: String) {
        let d = docker
        runTask("Pulling \(image)") { log in try await d.pull(image: image, onLine: log) }
    }

    func prune(_ kind: PruneKind) {
        let d = docker
        runTask("Cleaning up", notifyDone: true) { log in log(try await d.prune(kind)) }
    }
}

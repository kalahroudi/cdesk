// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 kalahroudi

import SwiftUI
import AppKit
import ColimaKit

/// `CDesk --snapshot <dir>` renders the app's screens to PNG files for the docs, then exits.
/// It uses made-up sample data, never your real containers.
enum SnapshotMode {
    nonisolated(unsafe) static var dir: String?

    @MainActor static func run() {
        guard let dir else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        NSApp.setActivationPolicy(.accessory)
        Demo.install()
        Task { @MainActor in
            for shot in shots { await render(shot, to: dir) }
            NSApp.terminate(nil)
        }
    }

    struct Shot { let name: String; let dark: Bool; let size: CGSize; let make: @MainActor () -> AnyView }

    @MainActor static var shots: [Shot] {
        func manager(_ s: Section, dark: Bool = false, sheet: SideSheet? = nil, stacks: Bool = false, agents: Bool = false) -> Shot {
            Shot(name: "manager-\(s.rawValue)\(stacks ? "-stacks" : "")\(agents ? "-agents" : "")\(sheet != nil ? "-sheet" : "")\(dark ? "-dark" : "")", dark: dark, size: CGSize(width: 1100, height: 740)) {
                Nav.shared.section = s; AppModel.shared.sheet = sheet
                return AnyView(ManagerView(stacksTab: stacks, agentsTab: agents))
            }
        }
        func setup() -> Shot {
            Shot(name: "manager-setup", dark: false, size: CGSize(width: 1100, height: 740)) {
                let m = AppModel.shared
                m.profiles = []; m.containers = []; m.stats = [:]; m.inventory = nil; m.sheet = nil
                m.setupState = SetupState(homebrew: true, colima: false, docker: false); m.missingTool = "colima"
                Nav.shared.section = .overview
                return AnyView(ManagerView())
            }
        }
        func pop(_ tab: PopoverView.Tab, dark: Bool = false) -> Shot {
            Shot(name: "popover-\(tab == .overview ? "overview" : "stacks")\(dark ? "-dark" : "")", dark: dark, size: CGSize(width: 800, height: 700)) { AnyView(PopoverShot(tab: tab)) }
        }
        return [pop(.overview), pop(.stacks), pop(.overview, dark: true),
                manager(.overview), manager(.profiles), manager(.profiles, sheet: .recreate), manager(.containers), manager(.containers, stacks: true),
                manager(.images), manager(.cleanup), manager(.settings), manager(.settings, agents: true), manager(.help), manager(.overview, dark: true), manager(.profiles, dark: true), setup()]
    }

    @MainActor static func render(_ shot: Shot, to dir: String) async {
        let host = NSHostingView(rootView: shot.make().frame(width: shot.size.width, height: shot.size.height))
        let win = NSWindow(contentRect: NSRect(origin: .zero, size: shot.size), styleMask: [.borderless], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: shot.dark ? .darkAqua : .aqua)
        win.contentView = host
        win.setFrameOrigin(NSPoint(x: -4000, y: 0))   // off screen, but still laid out and drawn
        win.orderFront(nil)
        try? await Task.sleep(for: .milliseconds(700))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(shot.name + ".png")) }
        win.orderOut(nil)
    }
}

/// A menu bar with the popover hanging from the icon, on a soft backdrop. Used only for screenshots.
struct PopoverShot: View {
    let tab: PopoverView.Tab
    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(colors: [Color(red: 0.62, green: 0.71, blue: 0.78), Color(red: 0.44, green: 0.54, blue: 0.66), Color(red: 0.29, green: 0.37, blue: 0.49)], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    Text("Finder").bold(); Text("File"); Text("Edit"); Text("View"); Text("Window")
                    Spacer()
                    Image(nsImage: StatusIcon.image(.running)).renderingMode(.template).padding(.horizontal, 6).padding(.vertical, 2).background(Color.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
                    Text("Tue 20 Oct  9:41")
                }.font(.system(size: 13)).foregroundStyle(.primary).padding(.horizontal, 14).frame(height: 28).background(.regularMaterial)
                ZStack(alignment: .top) {
                    PopoverView(initialTab: tab, openManager: { _ in })
                        .clipShape(RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.15)))
                        .shadow(color: .black.opacity(0.35), radius: 24, y: 12).padding(.top, 8)
                    Rectangle().fill(Theme.pane).frame(width: 14, height: 14).rotationEffect(.degrees(45)).offset(x: 108, y: 1)
                }.padding(.trailing, 10).frame(maxWidth: .infinity, alignment: .trailing)
                Spacer()
            }
        }
    }
}

/// Made-up data that looks like a typical day.
@MainActor enum Demo {
    static func install() {
        let m = AppModel.shared
        m.demo = true
        m.hardware = Hardware(memoryGiB: 16, totalCores: 8, performanceCores: 4, isAppleSilicon: true)
        Prefs.shared.sidebarCollapsed = false
        m.profiles = [Profile(name: "default", status: "Running", arch: "aarch64", cpus: 4, memory: 8 << 30, disk: 100 << 30, runtime: "docker", address: nil),
                      Profile(name: "heavy", status: "Stopped", arch: "aarch64", cpus: 6, memory: 12 << 30, disk: 100 << 30, runtime: "docker")]
        m.selected = "default"
        func c(_ id: String, _ name: String, _ image: String, _ up: Bool, _ ports: String, _ project: String?) -> Container {
            Container(id: id, name: name, image: image, state: up ? "running" : "exited", status: up ? "Up 2 hours" : "Exited (0) 3 hours ago", ports: ports, created: "2 hours ago", project: project, service: name)
        }
        m.containers = [c("a1b2c3d4e5f6", "shop-api-api-1", "node:22-alpine", true, "3000→3000", "shop-api"), c("b2c3d4e5f6a1", "shop-api-postgres-1", "postgres:16", true, "5432→5432", "shop-api"),
                        c("c3d4e5f6a1b2", "shop-api-redis-1", "redis:7-alpine", true, "6379→6379", "shop-api"), c("d4e5f6a1b2c3", "docs-site-web-1", "nginx:alpine", true, "8080→80", "docs-site"),
                        c("e5f6a1b2c3d4", "docs-site-builder-1", "docs-builder:dev", false, "", "docs-site"),
                        c("f6a1b2c3d4e5", "analytics-clickhouse-1", "clickhouse/clickhouse-server:24", false, "", "analytics"), c("0a1b2c3d4e5f", "analytics-grafana-1", "grafana/grafana:11", false, "", "analytics")]
        let mem: [String: Int64] = ["a1b2c3d4e5f6": 212, "b2c3d4e5f6a1": 148, "c3d4e5f6a1b2": 9, "d4e5f6a1b2c3": 6]
        let cpu: [String: Double] = ["a1b2c3d4e5f6": 1.8, "b2c3d4e5f6a1": 1.1, "c3d4e5f6a1b2": 0.2, "d4e5f6a1b2c3": 0.1]
        var stats: [String: ContainerStats] = [:]
        for (id, mb) in mem { stats[id] = ContainerStats(id: id, cpuPercent: cpu[id] ?? 0, memoryBytes: mb * 1_048_576, memoryLimitBytes: Int64(8) << 30) }
        m.stats = stats
        var samples: [Sample] = []
        for i in 0..<40 {
            let x = Double(i)
            let spike: Double = i % 9 == 0 ? 3 : 0
            let wave: Double = 2 * sin(x / 3)
            samples.append(Sample(cpu: 2.5 + wave + spike, memGiB: 1.3 + x * 0.002))
        }
        if ProcessInfo.processInfo.environment["CDESK_DEMO_MANY"] == "1" {
            for i in 0..<28 {
                let id = String(format: "%012x", 0xabc000 + i)
                m.containers.append(c(id, "service-\(i)-worker-1", "app/worker:\(i)", true, "", "fleet"))
                m.stats[id] = ContainerStats(id: id, cpuPercent: Double(i) / 10, memoryBytes: Int64(20 + i * 7) * 1_048_576, memoryLimitBytes: Int64(8) << 30)
            }
        }
        m.history = samples
        func img(_ id: String, _ r: String, _ t: String, _ size: String, _ n: Int, _ age: String) -> DockerImage { DockerImage(id: id, repository: r, tag: t, size: size, sizeBytes: parseSize(size), created: age, containers: n) }
        let images: [DockerImage] = [
            img("e1d93b2a7f50", "docs-builder", "dev", "1.9GB", 1, "5 weeks ago"), img("0f3a6e9b2d17", "<none>", "<none>", "1.1GB", 0, "6 weeks ago"),
            img("5d02e8b1c6a9", "postgres", "16", "431MB", 1, "3 weeks ago"), img("a91f3c07d2b4", "node", "22-alpine", "212MB", 1, "2 days ago"),
            img("7be0a5d41c88", "node", "20-alpine", "186MB", 0, "2 months ago"), img("b7c20d5a9e41", "nginx", "alpine", "52MB", 1, "1 week ago"),
            img("c4417fe09d31", "redis", "7-alpine", "41MB", 1, "3 weeks ago")]
        let volumes: [Volume] = [
            Volume(name: "shop-api_pgdata", driver: "local", size: "1.0GB", sizeBytes: 1_000_000_000, links: 1),
            Volume(name: "analytics_clickhouse", driver: "local", size: "120MB", sizeBytes: 120_000_000, links: 0),
            Volume(name: "shop-api_redisdata", driver: "local", size: "86MB", sizeBytes: 86_000_000, links: 1)]
        let usage: [DiskUsageRow] = [
            DiskUsageRow(type: "Images", total: 14, active: 5, size: "5.1GB", reclaimable: "3.2GB (62%)", reclaimableBytes: 3_200_000_000),
            DiskUsageRow(type: "Containers", total: 7, active: 4, size: "0.9GB", reclaimable: "0.8GB (88%)", reclaimableBytes: 800_000_000),
            DiskUsageRow(type: "Local Volumes", total: 3, active: 2, size: "1.2GB", reclaimable: "120MB (10%)", reclaimableBytes: 120_000_000),
            DiskUsageRow(type: "Build Cache", total: 18, active: 0, size: "2.2GB", reclaimable: "2.2GB", reclaimableBytes: 2_200_000_000)]
        m.inventory = DockerInventory(images: images, volumes: volumes, usage: usage)
        var saved = ColimaConfig(); saved.cpus = 4; saved.memoryGiB = 4; saved.diskGiB = 100; saved.mountType = .sshfs; saved.mountInotify = true
        m.saved = saved
        var draft = saved; draft.memoryGiB = 8; draft.mountType = .virtiofs; draft.dns = ["1.1.1.1", "8.8.8.8"]
        m.draft = draft
        m.loadedOnce = true; m.updatedAt = .now
        switch ProcessInfo.processInfo.environment["CDESK_DEMO_STATE"] {
        case "clean": m.draft = m.saved
        case "busy":
            var t = BackgroundTask(title: "Applying settings to default"); t.lines = ["Stopping colima…", "stopping vm"]
            m.tasks = [t]
        default: break
        }
    }
}

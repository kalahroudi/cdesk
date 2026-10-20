// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 kalahroudi

import SwiftUI
import ColimaKit

struct PopoverView: View {
    let model = AppModel.shared
    let nav = Nav.shared
    var openManager: (Section) -> Void
    @State private var tab: Tab
    enum Tab: Hashable { case overview, containers, stacks }
    init(initialTab: Tab = .overview, openManager: @escaping (Section) -> Void) { _tab = State(initialValue: initialTab); self.openManager = openManager }

    var body: some View {
        VStack(spacing: 12) {
            header
            if model.loadedOnce, model.needsSetup { SetupView(compact: true) }
            else if !model.loadedOnce { SkeletonList(rows: 5).frame(height: 220) }
            else {
                Segmented(options: [(Tab.overview, "Overview"), (Tab.containers, "Containers · \(model.containers.count)"), (Tab.stacks, "Stacks · \(model.stacks.count)")], selection: $tab)
                    .frame(maxWidth: .infinity)
                switch tab {
                case .overview: overview
                case .containers: containersTab
                case .stacks: stacksTab
                }
            }
            if let task = model.runningTask { TaskStrip(task: task) }
            footer
        }
        .padding(14)
        .frame(width: 380)
        .background(Theme.pane)
        .overlay(alignment: .bottom) { ToastView() }
        .onAppear { model.setPopoverVisible(true) }
        .onDisappear { model.setPopoverVisible(false) }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: AppIcon.image(size: 34)).resizable().frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("Colima").font(.system(size: 15, weight: .semibold))
                HStack(spacing: 6) {
                    StatusDot(color: model.busy ? Theme.warn : model.isRunning ? Theme.ok : .gray)
                    Text(statusLine).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if model.profiles.count > 1 {
                Menu(model.selected) {
                    ForEach(model.profiles) { p in Button(p.name) { model.select(profile: p.name) } }
                }.menuStyle(.borderlessButton).fixedSize()
            }
            Toggle("", isOn: Binding(get: { model.isRunning || model.busy }, set: { on in on ? model.startColima() : model.stopColima() }))
                .toggleStyle(.switch).labelsHidden().tint(Theme.ok).disabled(model.busy || model.missingTool != nil)
                .accessibilityLabel(model.isRunning ? "Stop Colima" : "Start Colima")
        }
    }

    private var statusLine: String {
        if let t = model.runningTask { return t.title + "…" }
        guard let p = model.profile else { return model.loadedOnce ? "No profile yet" : "Checking…" }
        return p.isRunning ? "Running · profile \(p.name)" : "Stopped · profile \(p.name)"
    }

    // MARK: Overview

    private var overview: some View {
        VStack(spacing: 12) {
            if model.isRunning, let p = model.profile {
                HStack(alignment: .top, spacing: 8) {
                    statCard("CPU", value: String(format: "%.1f", model.totalCPUPercent), unit: "% of \(p.cpus)") {
                        Sparkline(values: model.history.map(\.cpu)).frame(height: 22)
                    }
                    statCard("Memory", value: String(format: "%.1f", model.usedMemoryGiB ?? 0), unit: "/ \(Int(p.memoryGiB)) GB") {
                        UsageBar(fraction: (model.usedMemoryGiB ?? 0) / max(p.memoryGiB, 1))
                    }
                    statCard("Disk", value: "\(Int(p.diskGiB))", unit: "GB") {
                        UsageBar(fraction: min(1, Double(model.inventory?.usage.reduce(0) { $0 + parseSize($1.size) } ?? 0) / max(p.diskGiB * 1_000_000_000, 1)))
                    }
                }
                VStack(spacing: 0) {
                    row("Runtime", "\(model.profile?.runtime.capitalized ?? "") · \(p.arch)")
                    Divider()
                    HStack { Text("VM / Mount").foregroundStyle(.secondary); Spacer()
                        HStack(spacing: 4) { Badge(text: model.saved.vmType.rawValue.uppercased(), kind: .accent); Badge(text: model.saved.mountType.rawValue, kind: .accent); if model.saved.rosetta { Badge(text: "Rosetta", kind: .accent) } } }
                        .font(.system(size: 13)).padding(.vertical, 7)
                    if let a = p.address { Divider(); row("Address", a, mono: true) }
                }.padding(.horizontal, 12).background(Theme.card, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline))
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "power").font(.system(size: 26)).foregroundStyle(.secondary)
                    Text(model.busy ? "Working…" : "Colima is stopped").font(.system(size: 13, weight: .medium))
                    Text("Turn it on with the switch above. Nothing runs in the background while it is off.").font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding(.vertical, 22).card()
            }
            HStack(spacing: 8) {
                action("Restart", "arrow.clockwise") { model.restartColima() }.disabled(!model.isRunning || model.busy)
                action("SSH", "terminal") { TerminalLauncher.sshIntoVM(profile: model.selected) }.disabled(!model.isRunning)
                action("Prune", "trash") { Nav.shared.section = .cleanup; openManager(.cleanup) }.disabled(!model.isRunning)
                action("Settings", "slider.horizontal.3") { Nav.shared.section = .profiles; openManager(.profiles) }
            }
            if let inv = model.inventory, inv.reclaimableBytes > 500_000_000 {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles").foregroundStyle(Theme.warn)
                    Text("**\(formatBytes(inv.reclaimableBytes)) reclaimable** in unused images, containers and cache.").font(.system(size: 12))
                    Spacer()
                    Button("Clean up") { openManager(.cleanup) }.buttonStyle(Pill(kind: .primary))
                }.padding(10).background(Theme.warnSoft, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func statCard<C: View>(_ title: String, value: String, unit: String, @ViewBuilder viz: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(size: 19, weight: .semibold)); Text(unit).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            viz()
        }.frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading).card(padding: 10)
    }

    private func row(_ k: String, _ v: String, mono: Bool = false) -> some View {
        HStack { Text(k).foregroundStyle(.secondary); Spacer(); Text(v).font(mono ? .system(size: 12, design: .monospaced) : .system(size: 13)) }
            .font(.system(size: 13)).padding(.vertical, 7)
    }

    private func action(_ title: String, _ symbol: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 5) { Image(systemName: symbol).font(.system(size: 14)); Text(title).font(.system(size: 11.5)) }
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline))
        }.buttonStyle(.plain)
    }

    // MARK: Containers

    private var containersTab: some View {
        let shown = Array(model.containers.sorted { ($0.isRunning ? 0 : 1, $0.name) < ($1.isRunning ? 0 : 1, $1.name) }.prefix(7))
        return VStack(spacing: 0) {
            if shown.isEmpty { empty("No containers yet") }
            ForEach(shown) { c in
                ContainerRow(container: c, stats: model.stats[c.id]).padding(.horizontal, 12).padding(.vertical, 6)
                if c.id != shown.last?.id { Divider().padding(.leading, 28) }
            }
            if model.containers.count > shown.count {
                Divider()
                Button("\(model.containers.count - shown.count) more in Manager…") { openManager(.containers) }
                    .buttonStyle(.plain).foregroundStyle(Theme.accent).font(.system(size: 12.5, weight: .medium)).padding(8)
            }
        }.background(Theme.card, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline))
    }

    // MARK: Stacks

    private var stacksTab: some View {
        VStack(spacing: 8) {
            if model.stacks.isEmpty { empty("No Compose stacks. Start one with docker compose up.").card() }
            ForEach(model.stacks.prefix(5)) { s in StackCard(stack: s, compact: true) }
            if model.stacks.count > 5 { Button("\(model.stacks.count - 5) more in Manager…") { openManager(.containers) }.buttonStyle(.plain).foregroundStyle(Theme.accent).font(.system(size: 12.5, weight: .medium)) }
        }
    }

    private func empty(_ t: String) -> some View {
        Text(t).font(.system(size: 12.5)).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 18)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button { openManager(nav.section) } label: { Text("Open Manager…").fontWeight(.medium) + Text("  ⌘O").foregroundStyle(.secondary).font(.system(size: 11)) }
                .buttonStyle(.plain).foregroundStyle(Theme.accent).keyboardShortcut("o")
            Spacer()
            Button { Nav.shared.section = .settings; openManager(.settings) } label: { Image(systemName: "gearshape") }.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Settings")
            Button { NSApp.terminate(nil) } label: { Text("Quit") + Text("  ⌘Q").foregroundStyle(.secondary).font(.system(size: 11)) }
                .buttonStyle(.plain).foregroundStyle(.secondary).keyboardShortcut("q")
        }.font(.system(size: 13)).padding(.top, 8).overlay(alignment: .top) { Divider() }
    }
}

// MARK: Shared rows

struct ContainerRow: View {
    let container: Container
    let stats: ContainerStats?
    var model: AppModel { .shared }
    var body: some View {
        HStack(spacing: 9) {
            StatusDot(color: container.isRunning ? Theme.ok : .gray)
            VStack(alignment: .leading, spacing: 1) {
                Text(container.name).font(.system(size: 13)).lineLimit(1)
                Text([container.image, container.ports].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if let s = stats { Text(formatBytes(s.memoryBytes)).font(.system(size: 11.5)).foregroundStyle(.secondary) }
            if container.isRunning {
                MiniButton(symbol: "terminal", label: "Open shell in \(container.name)") { TerminalLauncher.shell(in: container, context: model.docker.context) }
                MiniButton(symbol: "stop.fill", label: "Stop \(container.name)") { model.perform(.stop, ids: [container.id]) }
            } else {
                MiniButton(symbol: "play.fill", label: "Start \(container.name)") { model.perform(.start, ids: [container.id]) }
            }
        }
    }
}

struct MiniButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10.5, weight: .medium)).frame(width: 26, height: 26)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
}

struct StackCard: View {
    let stack: Stack
    var compact = false
    @State private var open = true
    var model: AppModel { .shared }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { open.toggle() } label: { Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).frame(width: 14) }.buttonStyle(.plain)
                Text(stack.name).fontWeight(.semibold)
                Text("\(stack.runningCount) of \(stack.containers.count) running").font(.system(size: 12)).foregroundStyle(stack.runningCount == stack.containers.count ? .secondary : Theme.warn)
                Spacer()
                if stack.runningCount > 0 {
                    MiniButton(symbol: "arrow.clockwise", label: "Restart \(stack.name)") { model.perform(.restart, ids: stack.containers.map(\.id)) }
                    MiniButton(symbol: "stop.fill", label: "Stop \(stack.name)") { model.perform(.stop, ids: stack.containers.filter(\.isRunning).map(\.id)) }
                }
                if stack.runningCount < stack.containers.count {
                    MiniButton(symbol: "play.fill", label: "Start all in \(stack.name)") { model.perform(.start, ids: stack.containers.filter { !$0.isRunning }.map(\.id)) }
                }
            }.font(.system(size: 13)).padding(.horizontal, 12).padding(.vertical, 9)
            if open {
                ForEach(stack.containers) { c in
                    Divider()
                    ContainerRow(container: c, stats: model.stats[c.id]).padding(.leading, 26).padding(.trailing, 12).padding(.vertical, 6)
                }
            }
        }.background(Theme.card, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline))
    }
}

struct TaskStrip: View {
    let task: BackgroundTask
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 0) {
                Text(task.title).font(.system(size: 12, weight: .medium))
                Text(task.lines.last ?? "").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
        }.padding(9).background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 9))
    }
}

struct ToastView: View {
    let model = AppModel.shared
    var body: some View {
        if let t = model.toast {
            Text(t.message).font(.system(size: 12.5)).lineLimit(3).padding(.horizontal, 12).padding(.vertical, 8)
                .background(t.isError ? Theme.dangerSoft : Theme.card, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(t.isError ? Theme.danger.opacity(0.4) : Theme.hairline))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                .padding(.bottom, 44).padding(.horizontal, 14)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

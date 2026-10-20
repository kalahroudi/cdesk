// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 kalahroudi

import SwiftUI
import ColimaKit

struct ContainersPane: View {
    let model = AppModel.shared
    @State private var tab: Tab
    init(initialTab: Tab = .containers) { _tab = State(initialValue: initialTab) }
    @State private var query = ""
    @State private var page = 0
    @State private var selected: Set<String> = []
    @State private var focus: Container?
    enum Tab: Hashable { case containers, stacks, help }
    private let pageSize = 25

    private var filtered: [Container] {
        let q = query.lowercased()
        return model.containers
            .filter { q.isEmpty || $0.name.lowercased().contains(q) || $0.image.lowercased().contains(q) || $0.ports.contains(q) || ($0.project ?? "").lowercased().contains(q) }
            .sorted { ($0.isRunning ? 0 : 1, $0.name) < ($1.isRunning ? 0 : 1, $1.name) }
    }
    private var pageItems: [Container] { Array(filtered.dropFirst(page * pageSize).prefix(pageSize)) }

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: "Containers · \(model.selected)") {
                HStack(spacing: 8) { SearchBox(prompt: "Search name, image, port", text: $query).frame(width: 220) }
            } tabs: {
                TabBar(tabs: [(Tab.containers, "Containers · \(model.containers.count)"), (Tab.stacks, "Stacks · \(model.stacks.count)"), (Tab.help, "Help")], selection: $tab)
            }
            if !model.isRunning { notRunning }
            else {
                switch tab {
                case .containers: containers
                case .stacks: stacks
                case .help: ScrollView { GlossaryList(only: ["Stack", "Container", "Docker context"]).padding(22) }
                }
            }
        }
        .onChange(of: query) { page = 0 }
    }

    private var notRunning: some View {
        VStack(spacing: 10) {
            Image(systemName: "power").font(.system(size: 28)).foregroundStyle(.secondary)
            Text("Colima is stopped").font(.system(size: 14, weight: .semibold))
            Button("Start Colima") { model.startColima() }.buttonStyle(Pill(kind: .primary)).disabled(model.busy)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Containers tab

    private var containers: some View {
        VStack(spacing: 0) {
            if !selected.isEmpty { bulkBar }
            tableHeader
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(pageItems) { c in row(c); Divider() }
                    if filtered.isEmpty { Text(query.isEmpty ? "No containers yet" : "No containers match “\(query)”").foregroundStyle(.secondary).padding(40) }
                }
            }.background(Theme.card)
            Pager(total: filtered.count, noun: "containers", page: $page, pageSize: pageSize).background(Theme.card)
            Divider()
            detail
        }
    }

    private var bulkBar: some View {
        HStack(spacing: 10) {
            Text("\(selected.count) selected").font(.system(size: 12.5, weight: .semibold))
            Button("Select all \(filtered.count)") { selected = Set(filtered.map(\.id)) }.buttonStyle(.plain).foregroundStyle(Theme.accent).font(.system(size: 12.5, weight: .medium))
            Button("Clear") { selected = [] }.buttonStyle(.plain).foregroundStyle(.secondary).font(.system(size: 12.5))
            Spacer()
            Button("Start") { model.perform(.start, ids: Array(selected)); selected = [] }.buttonStyle(Pill())
            Button("Restart") { model.perform(.restart, ids: Array(selected)); selected = [] }.buttonStyle(Pill())
            Button("Stop") { model.perform(.stop, ids: Array(selected)); selected = [] }.buttonStyle(Pill())
            Button("Remove…") { model.sheet = .removeContainers(Array(selected)); selected = [] }.buttonStyle(Pill(kind: .danger))
        }.padding(.horizontal, 22).padding(.vertical, 7).background(Theme.accentSoft)
    }

    private var tableHeader: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { !pageItems.isEmpty && pageItems.allSatisfy { selected.contains($0.id) } }, set: { on in pageItems.forEach { if on { selected.insert($0.id) } else { selected.remove($0.id) } } }))
                .toggleStyle(.checkbox).labelsHidden().accessibilityLabel("Select all on this page")
            Text("Name").frame(maxWidth: .infinity, alignment: .leading)
            Text("Image").frame(width: 170, alignment: .leading)
            Text("Ports").frame(width: 120, alignment: .leading)
            Text("CPU").frame(width: 48, alignment: .trailing)
            Text("Memory").frame(width: 64, alignment: .trailing)
            Color.clear.frame(width: 88, height: 1)
        }.font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.horizontal, 22).padding(.vertical, 6).background(Theme.card).overlay(alignment: .bottom) { Divider() }
    }

    private func row(_ c: Container) -> some View {
        let s = model.stats[c.id]
        return HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { selected.contains(c.id) }, set: { on in if on { selected.insert(c.id) } else { selected.remove(c.id) } })).toggleStyle(.checkbox).labelsHidden().accessibilityLabel("Select \(c.name)")
            HStack(spacing: 8) { StatusDot(color: c.isRunning ? Theme.ok : .gray); VStack(alignment: .leading, spacing: 0) { Text(c.name).lineLimit(1); if let p = c.project { Text(p).font(.system(size: 10.5)).foregroundStyle(.secondary) } } }.frame(maxWidth: .infinity, alignment: .leading)
            Text(c.image).font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.middle).frame(width: 170, alignment: .leading)
            HStack(spacing: 2) { Text(c.ports.isEmpty ? "–" : c.ports).font(.system(size: 12, design: .monospaced)).lineLimit(1); if !c.ports.isEmpty { CopyButton(text: c.ports, label: "Copy ports") } }.frame(width: 120, alignment: .leading)
            Text(s.map { String(format: "%.1f%%", $0.cpuPercent) } ?? "–").font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 48, alignment: .trailing)
            Text(s.map { formatBytes($0.memoryBytes) } ?? "–").font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 64, alignment: .trailing)
            HStack(spacing: 4) {
                if c.isRunning { MiniButton(symbol: "terminal", label: "Open shell in \(c.name)") { TerminalLauncher.shell(in: c, context: model.docker.context) }
                    MiniButton(symbol: "stop.fill", label: "Stop \(c.name)") { model.perform(.stop, ids: [c.id]) } }
                else { MiniButton(symbol: "play.fill", label: "Start \(c.name)") { model.perform(.start, ids: [c.id]) } }
                menu(c)
            }.frame(width: 88, alignment: .trailing)
        }
        .font(.system(size: 13)).padding(.horizontal, 22).padding(.vertical, 6)
        .background(focus?.id == c.id ? Theme.accentSoft : .clear)
        .contentShape(Rectangle()).onTapGesture { focus = c }
        .contextMenu { menuItems(c) }
    }

    private func menu(_ c: Container) -> some View {
        Menu { menuItems(c) } label: { Image(systemName: "ellipsis").frame(width: 26, height: 26).background(Theme.fill, in: RoundedRectangle(cornerRadius: 6)) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("More actions for \(c.name)")
    }

    @ViewBuilder private func menuItems(_ c: Container) -> some View {
        if c.isRunning {
            Button("Open Shell") { TerminalLauncher.shell(in: c, context: model.docker.context) }
            Button("Open Shell as root") { TerminalLauncher.shell(in: c, context: model.docker.context, root: true) }
        }
        Button("Logs in Terminal") { TerminalLauncher.logs(of: c, context: model.docker.context) }
        Divider()
        Button("Copy docker exec command") { Clipboard.copy("docker --context \(model.docker.context) exec -it \(c.id) sh") }
        Button("Copy container ID") { Clipboard.copy(c.id) }
        Divider()
        if c.isRunning { Button("Restart") { model.perform(.restart, ids: [c.id]) }; Button("Stop") { model.perform(.stop, ids: [c.id]) } } else { Button("Start") { model.perform(.start, ids: [c.id]) } }
        Button("Remove…", role: .destructive) { model.sheet = .removeContainers([c.id]) }
    }

    @ViewBuilder private var detail: some View {
        if let c = focus ?? pageItems.first { LogPanel(container: c).frame(height: 190) }
    }

    // MARK: Stacks tab

    @State private var stackSel: Set<String> = []
    private var filteredStacks: [Stack] {
        let q = query.lowercased()
        return model.stacks.filter { q.isEmpty || $0.name.lowercased().contains(q) || $0.containers.contains { $0.name.lowercased().contains(q) } }
    }

    private var stacks: some View {
        let all = filteredStacks, items = Array(all.dropFirst(page * 10).prefix(10))
        return VStack(spacing: 0) {
            if !stackSel.isEmpty {
                HStack(spacing: 10) {
                    Text("\(stackSel.count) selected").font(.system(size: 12.5, weight: .semibold))
                    Button("Select all \(all.count)") { stackSel = Set(all.map(\.name)) }.buttonStyle(.plain).foregroundStyle(Theme.accent).font(.system(size: 12.5, weight: .medium))
                    Spacer()
                    Button("Start") { act(.start) }.buttonStyle(Pill()); Button("Restart") { act(.restart) }.buttonStyle(Pill()); Button("Stop") { act(.stop) }.buttonStyle(Pill())
                }.padding(.horizontal, 22).padding(.vertical, 7).background(Theme.accentSoft)
            }
            ScrollView {
                VStack(spacing: 10) {
                    if all.isEmpty { Text(query.isEmpty ? "No Compose stacks. Run docker compose up in a project to see one here." : "No stacks match “\(query)”").foregroundStyle(.secondary).padding(40) }
                    ForEach(items) { s in
                        HStack(alignment: .top, spacing: 8) {
                            Toggle("", isOn: Binding(get: { stackSel.contains(s.name) }, set: { on in if on { stackSel.insert(s.name) } else { stackSel.remove(s.name) } })).toggleStyle(.checkbox).labelsHidden().padding(.top, 11).accessibilityLabel("Select \(s.name)")
                            StackCard(stack: s)
                        }
                    }
                }.padding(22)
            }
            Pager(total: all.count, noun: "stacks", page: $page, pageSize: 10).background(Theme.card)
        }
    }

    private func act(_ a: ContainerAction) {
        let ids = model.stacks.filter { stackSel.contains($0.name) }.flatMap { s in s.containers.filter { a == .start ? !$0.isRunning : $0.isRunning || a == .restart }.map(\.id) }
        model.perform(a, ids: ids); stackSel = []
    }
}

/// Recent logs of one container, loaded when it is selected rather than streamed.
struct LogPanel: View {
    let container: Container
    @State private var text = ""
    @State private var loading = true
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Logs").font(.system(size: 12, weight: .semibold)); Text(container.name).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                CopyButton(text: text, label: "Copy logs")
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).accessibilityLabel("Refresh logs")
                Button("Follow in Terminal") { TerminalLauncher.logs(of: container, context: AppModel.shared.docker.context) }.buttonStyle(Pill())
            }.padding(.horizontal, 22).padding(.top, 8)
            ScrollView {
                if loading { ProgressView().controlSize(.small).padding(14) }
                else { Text(text.isEmpty ? "No output yet." : text).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Color(white: 0.85)).frame(maxWidth: .infinity, alignment: .leading).padding(12).textSelection(.enabled) }
            }.background(Theme.terminal, in: RoundedRectangle(cornerRadius: 10)).padding(.horizontal, 22).padding(.bottom, 12)
        }
        .task(id: container.id) { await load() }
    }

    private func load() async {
        loading = true
        if AppModel.shared.demo {
            text = "09:41:02  server listening on :3000\n09:41:03  connected to postgres://postgres:5432/shop\n09:41:19  GET /health 200 2ms\n09:41:31  GET /v1/products?limit=20 200 14ms\n09:41:44  warn slow query 312ms: select * from orders\n09:41:52  POST /v1/cart 201 9ms"
        } else {
            text = (try? await AppModel.shared.docker.logs(id: container.id, tail: 200)) ?? "Couldn't read logs."
        }
        loading = false
    }
}

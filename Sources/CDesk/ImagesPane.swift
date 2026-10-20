// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 kalahroudi

import SwiftUI
import ColimaKit

struct ImagesPane: View {
    let model = AppModel.shared
    @State private var tab = Tab.images
    @State private var query = ""
    @State private var page = 0
    @State private var selected: Set<String> = []
    enum Tab: Hashable { case images, volumes, help }
    private let pageSize = 25

    private var images: [DockerImage] {
        let q = query.lowercased()
        return (model.inventory?.images ?? []).filter { q.isEmpty || $0.reference.lowercased().contains(q) || $0.id.contains(q) }
    }
    private var volumes: [Volume] {
        let q = query.lowercased()
        return (model.inventory?.volumes ?? []).filter { q.isEmpty || $0.name.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: "Images & Volumes · \(model.selected)") {
                HStack(spacing: 8) {
                    SearchBox(prompt: "Search name or tag", text: $query).frame(width: 220)
                    Button("Pull image…") { model.sheet = .pullImage }.buttonStyle(Pill(kind: .primary)).disabled(!model.isRunning)
                }
            } tabs: {
                TabBar(tabs: [(Tab.images, "Images · \(model.inventory?.images.count ?? 0)"), (Tab.volumes, "Volumes · \(model.inventory?.volumes.count ?? 0)"), (Tab.help, "Help")], selection: $tab)
            }
            if !model.isRunning { Text("Start Colima to see images and volumes.").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if model.inventory == nil { SkeletonList(rows: 8).frame(maxHeight: .infinity, alignment: .top) }
            else {
                switch tab {
                case .images: imageList
                case .volumes: volumeList
                case .help: ScrollView { GlossaryList(only: ["Image", "Dangling image", "Volume", "Build cache"]).padding(22) }
                }
            }
        }
        .onChange(of: query) { page = 0 }
        .onChange(of: tab) { page = 0; selected = [] }
    }

    // MARK: Images

    private var imageList: some View {
        let all = images, items = Array(all.dropFirst(page * pageSize).prefix(pageSize))
        let unused = all.filter { !$0.isUsed }
        return VStack(spacing: 0) {
            if !selected.isEmpty {
                HStack(spacing: 10) {
                    Text("\(selected.count) selected · \(formatBytes(all.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.sizeBytes }))").font(.system(size: 12.5, weight: .semibold))
                    Button("Select all unused (\(unused.count))") { selected = Set(unused.map(\.id)) }.buttonStyle(.plain).foregroundStyle(Theme.accent).font(.system(size: 12.5, weight: .medium))
                    Button("Clear") { selected = [] }.buttonStyle(.plain).foregroundStyle(.secondary).font(.system(size: 12.5))
                    Spacer()
                    Button("Remove…") { model.sheet = .removeImages(all.filter { selected.contains($0.id) }.map { $0.isDangling ? $0.id : $0.reference }); selected = [] }.buttonStyle(Pill(kind: .danger))
                }.padding(.horizontal, 22).padding(.vertical, 7).background(Theme.accentSoft)
            } else if !unused.isEmpty {
                HStack { Text("\(unused.count) unused images").font(.system(size: 12)).foregroundStyle(.secondary); Button("Select all unused") { selected = Set(unused.map(\.id)) }.buttonStyle(.plain).foregroundStyle(Theme.accent).font(.system(size: 12, weight: .medium)); Spacer() }.padding(.horizontal, 22).padding(.vertical, 6).background(Theme.pane)
            }
            HStack(spacing: 10) {
                Toggle("", isOn: Binding(get: { !items.isEmpty && items.allSatisfy { selected.contains($0.id) } }, set: { on in items.forEach { if on { selected.insert($0.id) } else { selected.remove($0.id) } } })).toggleStyle(.checkbox).labelsHidden().accessibilityLabel("Select all on this page")
                Text("Repository : tag").frame(maxWidth: .infinity, alignment: .leading); Text("Image ID").frame(width: 130, alignment: .leading); Text("Size").frame(width: 70, alignment: .trailing); Text("Created").frame(width: 90, alignment: .leading); Text("Status").frame(width: 110, alignment: .leading); Color.clear.frame(width: 28, height: 1)
            }.font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.horizontal, 22).padding(.vertical, 6).background(Theme.card).overlay(alignment: .bottom) { Divider() }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { i in
                        HStack(spacing: 10) {
                            Toggle("", isOn: Binding(get: { selected.contains(i.id) }, set: { on in if on { selected.insert(i.id) } else { selected.remove(i.id) } })).toggleStyle(.checkbox).labelsHidden().accessibilityLabel("Select \(i.reference)")
                            (i.isDangling ? Text("<none>").foregroundStyle(.secondary) : Text(i.repository).fontWeight(.medium) + Text(":\(i.tag)").foregroundStyle(.secondary)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            HStack(spacing: 2) { Text(i.id).font(.system(size: 12, design: .monospaced)); CopyButton(text: i.id, label: "Copy image ID") }.frame(width: 130, alignment: .leading)
                            Text(i.size).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 70, alignment: .trailing)
                            Text(i.created).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                            Group { if i.isDangling { Badge(text: "Dangling") } else if i.isUsed { Badge(text: "In use · \(i.containers)", kind: .ok) } else { Badge(text: "Unused", kind: .warn) } }.frame(width: 110, alignment: .leading)
                            Menu { Button("Copy reference") { Clipboard.copy(i.reference) }; Button("Remove…", role: .destructive) { model.sheet = .removeImages([i.isDangling ? i.id : i.reference]) }.disabled(i.isUsed) } label: { Image(systemName: "ellipsis").frame(width: 24, height: 24) }
                                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("More actions")
                        }.font(.system(size: 13)).padding(.horizontal, 22).padding(.vertical, 7).background(selected.contains(i.id) ? Theme.accentSoft : .clear)
                        Divider()
                    }
                    if all.isEmpty { Text(query.isEmpty ? "No images" : "No images match “\(query)”").foregroundStyle(.secondary).padding(40) }
                }
            }.background(Theme.card)
            Pager(total: all.count, noun: "images", page: $page, pageSize: pageSize).background(Theme.card)
        }
    }

    // MARK: Volumes

    private var volumeList: some View {
        let all = volumes, items = Array(all.dropFirst(page * pageSize).prefix(pageSize))
        return VStack(spacing: 0) {
            HStack(spacing: 8) { Image(systemName: "externaldrive.badge.exclamationmark").foregroundStyle(.secondary); Text("Volumes hold data such as databases. Removing one asks you to type its name, and volumes in use can't be removed.").font(.system(size: 12)).foregroundStyle(.secondary); Spacer() }.padding(.horizontal, 22).padding(.vertical, 8).background(Theme.pane)
            HStack(spacing: 10) {
                Text("Name").frame(maxWidth: .infinity, alignment: .leading); Text("Used by").frame(width: 90, alignment: .leading); Text("Size").frame(width: 70, alignment: .trailing); Text("Status").frame(width: 100, alignment: .leading); Color.clear.frame(width: 28, height: 1)
            }.font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.horizontal, 22).padding(.vertical, 6).background(Theme.card).overlay(alignment: .bottom) { Divider() }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { v in
                        HStack(spacing: 10) {
                            HStack(spacing: 2) { Text(v.name).font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.middle); CopyButton(text: v.name, label: "Copy volume name") }.frame(maxWidth: .infinity, alignment: .leading)
                            Text(v.isUsed ? "\(v.links) container\(v.links == 1 ? "" : "s")" : "not used").font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                            Text(v.size).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 70, alignment: .trailing)
                            Group { v.isUsed ? Badge(text: "Protected", kind: .accent) : Badge(text: "Unused", kind: .warn) }.frame(width: 100, alignment: .leading)
                            Button { model.sheet = .removeVolume(v.name) } label: { Image(systemName: "trash").font(.system(size: 12)).frame(width: 26, height: 26).background(Theme.fill, in: RoundedRectangle(cornerRadius: 6)) }
                                .buttonStyle(.plain).disabled(v.isUsed).opacity(v.isUsed ? 0.35 : 1).accessibilityLabel("Remove volume \(v.name)")
                        }.font(.system(size: 13)).padding(.horizontal, 22).padding(.vertical, 7)
                        Divider()
                    }
                    if all.isEmpty { Text(query.isEmpty ? "No volumes" : "No volumes match “\(query)”").foregroundStyle(.secondary).padding(40) }
                }
            }.background(Theme.card)
            Pager(total: all.count, noun: "volumes", page: $page, pageSize: pageSize).background(Theme.card)
        }
    }
}

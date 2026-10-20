// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 kalahroudi

import SwiftUI
import ColimaKit

/// Right-side overlay for actions. It closes itself when the action is started, and the result appears behind it.
struct SheetHost: View {
    let model = AppModel.shared
    var body: some View {
        ZStack(alignment: .trailing) {
            if let s = model.sheet {
                Color.black.opacity(0.35).ignoresSafeArea().onTapGesture { model.sheet = nil }.transition(.opacity)
                SheetContent(sheet: s)
                    .frame(width: 470).frame(maxHeight: .infinity)
                    .background(Theme.pane)
                    .shadow(color: .black.opacity(0.3), radius: 20, x: -8)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.sheet)
        .onExitCommand { model.sheet = nil }
    }
}

struct SheetContent: View {
    let sheet: SideSheet
    var body: some View {
        switch sheet {
        case .recreate: RecreateSheet()
        case .pullImage: PullSheet()
        case .newProfile: NewProfileSheet()
        case .prune(let k): PruneSheet(kind: k)
        case .removeContainers(let ids): ConfirmSheet(title: "Remove \(ids.count) container\(ids.count == 1 ? "" : "s")?", message: "Running containers are stopped first. Their writable layers are deleted. Volumes are kept.", confirm: "Remove", destructive: true) { AppModel.shared.removeContainers(ids) }
        case .removeImages(let refs): ConfirmSheet(title: "Remove \(refs.count) image\(refs.count == 1 ? "" : "s")?", message: "You can pull them again later. Images used by a container cannot be removed.", confirm: "Remove", destructive: true) { AppModel.shared.removeImages(refs) }
        case .removeVolume(let name): TypeToConfirmSheet(title: "Remove volume", warning: "This permanently deletes the volume and all data in it. It cannot be undone.", name: name, action: "Remove volume") { AppModel.shared.removeVolume(name) }
        case .removeProfile(let name): TypeToConfirmSheet(title: "Delete profile", warning: "This deletes the VM and every container, image and volume inside it.", name: name, action: "Delete profile") { AppModel.shared.deleteProfile(name) }
        }
    }
}

/// Header, scrolling body, footer: shared by every sheet.
struct SheetFrame<Body: View, Footer: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Body
    @ViewBuilder var footer: Footer
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 17, weight: .semibold))
                    if let s = subtitle { Text(s).font(.system(size: 12)).foregroundStyle(.secondary) }
                }
                Spacer()
                Button { AppModel.shared.sheet = nil } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).frame(width: 24, height: 24).background(Theme.fill, in: Circle()) }
                    .buttonStyle(.plain).accessibilityLabel("Close")
            }.padding(.horizontal, 20).padding(.top, 38).padding(.bottom, 12)
            Divider()
            ScrollView { VStack(alignment: .leading, spacing: 16) { content }.padding(20).frame(maxWidth: .infinity, alignment: .leading) }
            Divider()
            HStack(spacing: 10) { Spacer(); footer }.padding(14).background(Theme.sidebar.opacity(0.6))
        }
    }
}

/// Shows the exact name to type, with a copy icon attached (no padding between), and a field to type it in.
struct TypeToConfirm: View {
    let name: String
    @Binding var typed: String
    var matches: Bool { typed == name }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Type the name to confirm:").font(.system(size: 12.5))
            HStack(spacing: 0) {
                Text(name).font(.system(size: 14, weight: .semibold, design: .monospaced)).padding(.horizontal, 8).frame(height: 30).background(Theme.fill)
                Button { Clipboard.copy(name) } label: { Image(systemName: "doc.on.doc").font(.system(size: 12)).frame(width: 28, height: 30).background(Theme.fill.opacity(1.6)) }
                    .buttonStyle(.plain).accessibilityLabel("Copy name")
            }.clipShape(RoundedRectangle(cornerRadius: 6))
            TextField("", text: $typed).textFieldStyle(.plain).font(.system(size: 14, design: .monospaced)).padding(9)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(typed.isEmpty ? Theme.hairline : matches ? Theme.ok : Theme.danger, lineWidth: 1.5))
                .accessibilityLabel("Type \(name) to confirm")
            if !typed.isEmpty && !matches { Text("Doesn’t match yet").font(.system(size: 11.5)).foregroundStyle(Theme.danger) }
        }
    }
}

struct ConfirmSheet: View {
    let title: String
    let message: String
    let confirm: String
    var destructive = false
    let action: () -> Void
    var body: some View {
        SheetFrame(title: title) {
            Text(message).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        } footer: {
            Button("Cancel") { AppModel.shared.sheet = nil }.buttonStyle(Pill()).keyboardShortcut(.cancelAction)
            Button(confirm) { AppModel.shared.sheet = nil; action() }.buttonStyle(Pill(kind: destructive ? .danger : .primary)).keyboardShortcut(.defaultAction)
        }
    }
}

struct TypeToConfirmSheet: View {
    let title: String
    let warning: String
    let name: String
    let action: String
    let run: () -> Void
    @State private var typed = ""
    var body: some View {
        SheetFrame(title: title, subtitle: name) {
            Label { Text(warning).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.danger) }
                .padding(12).background(Theme.dangerSoft, in: RoundedRectangle(cornerRadius: 9))
            TypeToConfirm(name: name, typed: $typed)
        } footer: {
            Button("Cancel") { AppModel.shared.sheet = nil }.buttonStyle(Pill()).keyboardShortcut(.cancelAction)
            Button(action) { AppModel.shared.sheet = nil; run() }.buttonStyle(Pill(kind: .danger)).disabled(typed != name)
        }
    }
}

// MARK: Recreate

struct RecreateSheet: View {
    let model = AppModel.shared
    @State private var typed = ""
    @State private var exportVolumes = true
    @State private var saveYAML = true
    var name: String { model.selected }
    var usedVolumes: [Volume] { (model.inventory?.volumes ?? []).filter(\.isUsed) }

    var body: some View {
        SheetFrame(title: "Recreate VM", subtitle: "Profile \(name) · applies \(model.recreateReasons.count + (model.restartPending ? 1 : 0)) change\(model.recreateReasons.count + (model.restartPending ? 1 : 0) == 1 ? "" : "s")") {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("What changes")
                VStack(spacing: 0) {
                    ForEach(changeRows, id: \.0) { r in
                        HStack { Text(r.0); Spacer(); Text(r.1).font(.system(size: 12, design: .monospaced)) }.font(.system(size: 13)).padding(.vertical, 8)
                        if r.0 != changeRows.last?.0 { Divider() }
                    }
                }.padding(.horizontal, 12).background(Theme.card, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline))
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("What happens to your data")
                HStack(spacing: 8) {
                    stateCard("Now", "VM · \(model.saved.mountType.rawValue)", "\(model.containers.count) containers\n\(model.inventory?.images.count ?? 0) images · \(model.inventory?.volumes.count ?? 0) volumes", dashed: false)
                    VStack(spacing: 2) { Image(systemName: "arrow.right").foregroundStyle(Theme.danger); Text("delete &\nrebuild").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.danger).multilineTextAlignment(.center) }.frame(width: 66)
                    stateCard("After", "VM · \(model.draft.mountType.rawValue)", "empty VM\nre-pull images", dashed: true)
                }
                HStack(alignment: .top, spacing: 8) {
                    note("Kept", "Project files on your Mac, Dockerfiles, compose files, colima.yaml", Theme.ok, Theme.ok.opacity(0.12))
                    note("Deleted", "Containers, images, volumes and build cache inside the VM", Theme.danger, Theme.dangerSoft)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("Back up first")
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $exportVolumes) { Text("Export \(usedVolumes.count) volume\(usedVolumes.count == 1 ? "" : "s") to ~/Colima Backups/\(name)/") }.disabled(usedVolumes.isEmpty)
                    Toggle(isOn: $saveYAML) { Text("Save a copy of colima.yaml and the image list") }
                }.toggleStyle(.checkbox).font(.system(size: 13)).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Theme.card, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline))
            }
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("Confirm")
                Text("This deletes the VM and everything inside it.").font(.system(size: 12.5))
                TypeToConfirm(name: name, typed: $typed)
            }
        } footer: {
            Button("Cancel") { model.sheet = nil }.buttonStyle(Pill()).keyboardShortcut(.cancelAction)
            Button("Recreate VM") { model.sheet = nil; model.recreate(config: model.draft, backup: .init(volumes: exportVolumes ? usedVolumes.map(\.name) : [], files: saveYAML)) }
                .buttonStyle(Pill(kind: .danger)).disabled(typed != name)
        }
    }

    private var changeRows: [(String, String)] {
        var rows: [(String, String)] = []
        let o = model.saved, n = model.draft
        if o.vmType != n.vmType { rows.append(("VM type", "\(o.vmType.rawValue) → \(n.vmType.rawValue)")) }
        if o.mountType != n.mountType { rows.append(("Mount type", "\(o.mountType.rawValue) → \(n.mountType.rawValue)")) }
        if o.arch != n.arch { rows.append(("Architecture", "\(o.arch) → \(n.arch)")) }
        if o.runtime != n.runtime { rows.append(("Runtime", "\(o.runtime.rawValue) → \(n.runtime.rawValue)")) }
        if o.cpus != n.cpus { rows.append(("CPUs", "\(o.cpus) → \(n.cpus)")) }
        if o.memoryGiB != n.memoryGiB { rows.append(("Memory", "\(Int(o.memoryGiB)) → \(Int(n.memoryGiB)) GB")) }
        if o.diskGiB != n.diskGiB { rows.append(("Disk", "\(o.diskGiB) → \(n.diskGiB) GB")) }
        return rows.isEmpty ? [("Settings", "unchanged")] : rows
    }

    private func stateCard(_ label: String, _ title: String, _ body: String, dashed: Bool) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(body).font(.system(size: 11.5)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(10)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(dashed ? Theme.accent : Theme.hairline, style: StrokeStyle(lineWidth: 1, dash: dashed ? [4, 3] : [])))
    }

    private func note(_ title: String, _ text: String, _ fg: Color, _ bg: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) { Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(fg); Text(text).font(.system(size: 12)) }
            .frame(maxWidth: .infinity, alignment: .leading).padding(10).background(bg, in: RoundedRectangle(cornerRadius: 9))
    }
}

// MARK: Pull, new profile, prune

struct PullSheet: View {
    @State private var ref = ""
    var body: some View {
        SheetFrame(title: "Pull image", subtitle: "Downloads in the background") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Image").font(.system(size: 12.5, weight: .medium))
                TextField("postgres:16", text: $ref).textFieldStyle(.plain).font(.system(size: 14, design: .monospaced)).padding(9)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline))
                Text("Use name:tag, for example node:22-alpine. Without a tag Docker pulls latest.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        } footer: {
            Button("Cancel") { AppModel.shared.sheet = nil }.buttonStyle(Pill()).keyboardShortcut(.cancelAction)
            Button("Pull") { AppModel.shared.sheet = nil; AppModel.shared.pull(ref.trimmingCharacters(in: .whitespaces)) }.buttonStyle(Pill(kind: .primary)).disabled(ref.trimmingCharacters(in: .whitespaces).isEmpty).keyboardShortcut(.defaultAction)
        }
    }
}

struct ProfileTemplate: Identifiable {
    let id: String; let title: String; let blurb: String; let config: ColimaConfig
    static func all(_ rec: Recommendation) -> [ProfileTemplate] {
        func c(_ cpus: Int, _ mem: Double, _ disk: Int) -> ColimaConfig { var x = ColimaConfig(); x.cpus = cpus; x.memoryGiB = mem; x.diskGiB = disk; x.mountInotify = true; x.dns = ["1.1.1.1", "8.8.8.8"]; return x }
        return [ProfileTemplate(id: "recommended", title: "Recommended for this Mac", blurb: "\(rec.cpus) CPU · \(Int(rec.memoryGiB)) GB · \(rec.diskGiB) GB", config: c(rec.cpus, rec.memoryGiB, rec.diskGiB)),
                ProfileTemplate(id: "minimal", title: "Minimal", blurb: "1 CPU · 2 GB · 30 GB. Quick tests.", config: c(1, 2, 30)),
                ProfileTemplate(id: "heavy", title: "Heavy", blurb: "6 CPU · 12 GB · 100 GB. Big builds and integration tests.", config: c(6, 12, 100))]
    }
}

struct NewProfileSheet: View {
    let model = AppModel.shared
    @State private var name = ""
    @State private var pick = "recommended"
    var valid: Bool { !name.isEmpty && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" } && !model.profiles.contains { $0.name == name } }
    var body: some View {
        let templates = ProfileTemplate.all(model.recommendation)
        SheetFrame(title: "New profile", subtitle: "A separate VM with its own settings") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Name").font(.system(size: 12.5, weight: .medium))
                TextField("heavy", text: $name).textFieldStyle(.plain).font(.system(size: 14, design: .monospaced)).padding(9)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline))
                Text("Letters, numbers, - and _. Docker context will be colima-\(name.isEmpty ? "name" : name).").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Start from").font(.system(size: 12.5, weight: .medium))
                ForEach(templates) { t in
                    Button { pick = t.id } label: {
                        HStack { VStack(alignment: .leading, spacing: 2) { Text(t.title).font(.system(size: 13, weight: .semibold)); Text(t.blurb).font(.system(size: 12)).foregroundStyle(.secondary) }; Spacer()
                            Image(systemName: pick == t.id ? "largecircle.fill.circle" : "circle").foregroundStyle(pick == t.id ? Theme.accent : .secondary) }
                            .padding(11).background(Theme.card, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(pick == t.id ? Theme.accent : Theme.hairline, lineWidth: pick == t.id ? 1.5 : 1))
                    }.buttonStyle(.plain)
                }
                Text("All use vz and virtiofs with fixed DNS and file-change events. You can adjust everything afterwards.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        } footer: {
            Button("Cancel") { model.sheet = nil }.buttonStyle(Pill()).keyboardShortcut(.cancelAction)
            Button("Create & start") { model.sheet = nil; model.createProfile(name: name, config: templates.first { $0.id == pick }!.config) }.buttonStyle(Pill(kind: .primary)).disabled(!valid).keyboardShortcut(.defaultAction)
        }
    }
}

struct PruneSheet: View {
    let kind: PruneKind
    let model = AppModel.shared
    @State private var typed = ""
    var info: (title: String, body: String, size: Int64, destructive: Bool) {
        let usage = model.inventory?.usage ?? []
        func rec(_ t: String) -> Int64 { usage.first { $0.type == t }?.reclaimableBytes ?? 0 }
        switch kind {
        case .danglingImages: return ("Remove dangling images", "Untagged layers left behind by rebuilds. Safe to remove.", 0, false)
        case .unusedImages: return ("Remove all unused images", "Every image that no container uses. You can pull them again later.", rec("Images"), false)
        case .stoppedContainers: return ("Remove stopped containers", "Deletes exited containers and their writable layers. Volumes are kept.", rec("Containers"), false)
        case .unusedVolumes: return ("Remove unused volumes", "Deletes volumes that no container uses, including their data. This cannot be undone.", rec("Local Volumes"), true)
        case .buildCache: return ("Clear build cache", "Next builds will be slower once, then fast again.", rec("Build Cache"), false)
        }
    }
    var body: some View {
        let i = info
        SheetFrame(title: i.title, subtitle: i.size > 0 ? "Frees up to \(formatBytes(i.size))" : nil) {
            Text(i.body).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            if i.destructive { TypeToConfirm(name: model.selected, typed: $typed) }
        } footer: {
            Button("Cancel") { model.sheet = nil }.buttonStyle(Pill()).keyboardShortcut(.cancelAction)
            Button("Clean up") { model.sheet = nil; model.prune(kind) }.buttonStyle(Pill(kind: i.destructive ? .danger : .primary)).disabled(i.destructive && typed != model.selected).keyboardShortcut(.defaultAction)
        }
    }
}

// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 kalahroudi

import SwiftUI
import AppKit
import ColimaKit

struct ProfilesPane: View {
    let model = AppModel.shared
    @State private var tab = Tab.settings
    @State private var showAdvanced = false
    enum Tab: Hashable { case settings, yaml, help }

    var body: some View {
        @Bindable var m = model
        VStack(spacing: 0) {
            PaneHeader(title: "Profile: \(model.selected)", subtitle: "Every colima start option, grouped. Settings with a lock need the VM to be recreated.") {
                HStack(spacing: 8) {
                    if model.profile != nil {
                        Menu("Repair") {
                            Button("Force stop & restart (VM stuck)") { model.repairForceRestart() }
                            Button("Re-register Docker context") { model.repairDockerContext() }
                            Button("Use fixed DNS & restart (no internet in containers)") { model.repairDNS() }
                        }.menuStyle(.borderlessButton).fixedSize().disabled(model.busy)
                    }
                    if model.profile != nil { Button("Delete…") { model.sheet = .removeProfile(model.selected) }.buttonStyle(Pill(kind: .danger)) }
                    Button("New profile") { model.sheet = .newProfile }.buttonStyle(Pill())
                }
            } tabs: {
                VStack(alignment: .leading, spacing: 4) {
                    profileChips
                    TabBar(tabs: [(Tab.settings, "Settings"), (Tab.yaml, "YAML"), (Tab.help, "Help")], selection: $tab)
                }
            }
            switch tab {
            case .settings: settings
            case .yaml: yaml
            case .help: ScrollView { GlossaryList().padding(22) }
            }
        }
    }

    private var profileChips: some View {
        HStack(spacing: 6) {
            ForEach(model.profiles) { p in
                Button { model.select(profile: p.name) } label: {
                    HStack(spacing: 5) { StatusDot(color: p.isRunning ? Theme.ok : .gray); Text(p.name).font(.system(size: 12.5, weight: model.selected == p.name ? .semibold : .regular)) }
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(model.selected == p.name ? Theme.accentSoft : Theme.fill, in: Capsule())
                }.buttonStyle(.plain)
            }
        }.padding(.bottom, 4)
    }

    // MARK: Settings tab

    private var locked: Bool { model.profile != nil }

    private var settings: some View {
        @Bindable var m = model
        return VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        recommendationBanner
                        group("Resources", "can change · a restart applies them") {
                            FormRow("CPUs", flag: "--cpus", help: ("CPUs", "How many of your Mac's cores the VM may use. About half is a good start: enough for builds, and your editor and browser keep the rest."), changed: m.draft.cpus != m.saved.cpus) {
                                SliderField(value: Binding(get: { Double(m.draft.cpus) }, set: { m.draft.cpus = Int($0) }), range: 1...Double(model.hardware.totalCores), step: 1, label: "\(m.draft.cpus) cores")
                            }
                            FormRow("Memory", flag: "--memory", help: ("Memory", "RAM reserved for the VM. Giving it about 50% of your Mac's RAM leaves macOS enough room to avoid swapping."), changed: m.draft.memoryGiB != m.saved.memoryGiB, note: m.draft.memoryGiB != m.saved.memoryGiB ? "\(Int(m.saved.memoryGiB)) → \(Int(m.draft.memoryGiB)) GB" : nil) {
                                SliderField(value: $m.draft.memoryGiB, range: 1...max(2, model.hardware.memoryGiB), step: 1, label: "\(Int(m.draft.memoryGiB)) GB")
                            }
                            FormRow("Disk", flag: "--disk", help: ("Disk", "Size of the VM's disk. It can only be increased, never shrunk, so start with a size that leaves room for image caching (100 GB is common)."), lock: locked ? "grow only" : nil, changed: m.draft.diskGiB != m.saved.diskGiB) {
                                SliderField(value: Binding(get: { Double(m.draft.diskGiB) }, set: { m.draft.diskGiB = Int($0) }), range: Double(locked ? m.saved.diskGiB : 20)...500, step: 5, label: "\(m.draft.diskGiB) GB")
                            }
                        }
                        group("Virtualization", locked ? "fixed when the VM is created" : "chosen when the VM is created") {
                            FormRow("VM type", flag: "--vm-type", help: ("VM type", "vz uses Apple's Virtualization framework: faster to start, lower energy, and it enables virtiofs and Rosetta. qemu is a slower software emulator. krunkit is experimental."), lock: locked ? "recreate" : nil, changed: m.draft.vmType != m.saved.vmType) {
                                Segmented(options: VMType.allCases.map { ($0, $0 == .vz ? "VZ" : $0.rawValue.uppercased()) }, selection: $m.draft.vmType)
                            }
                            FormRow("Mount type", flag: "--mount-type", help: ("Mount type", "How your Mac's folders appear inside containers. virtiofs is the fastest and works with vz. sshfs and 9p are slower, noticeable with npm install and builds."), lock: locked ? "recreate" : nil, changed: m.draft.mountType != m.saved.mountType, note: m.draft.mountType != m.saved.mountType ? "\(m.saved.mountType.rawValue) → \(m.draft.mountType.rawValue)" : nil) {
                                Segmented(options: MountType.allCases.map { ($0, $0.rawValue) }, selection: $m.draft.mountType)
                            }
                            FormRow("Rosetta for amd64 images", flag: "--vz-rosetta", help: ("Rosetta", "Lets the VM run linux/amd64 images using Apple's translation layer, much faster than emulating. Leave it off if all your images are arm64."), changed: m.draft.rosetta != m.saved.rosetta, note: model.hasAmd64 ? nil : "off · no amd64 images found") {
                                Toggle("", isOn: $m.draft.rosetta).labelsHidden().toggleStyle(.switch).tint(Theme.accent).disabled(m.draft.vmType != .vz)
                            }
                            FormRow("Architecture", flag: "--arch", help: ("Architecture", "aarch64 runs natively on Apple silicon. Choose x86_64 only if you must emulate Intel for everything (slow)."), lock: locked ? "recreate" : nil, changed: m.draft.arch != m.saved.arch) {
                                Segmented(options: [("aarch64", "aarch64"), ("x86_64", "x86_64")], selection: $m.draft.arch)
                            }
                            FormRow("Runtime", flag: "--runtime", help: ("Runtime", "docker is what most people want. containerd and incus are alternatives."), lock: locked ? "recreate" : nil, changed: m.draft.runtime != m.saved.runtime) {
                                Segmented(options: RuntimeKind.allCases.map { ($0, $0.rawValue) }, selection: $m.draft.runtime)
                            }
                        }
                        group("Files & network", "can change · a restart applies them") {
                            FormRow("File-change events (inotify)", flag: "--mount-inotify", help: ("inotify", "Passes file edits made on your Mac into the VM so watchers like nodemon, Vite and webpack notice them without polling. Colima marks it experimental."), changed: m.draft.mountInotify != m.saved.mountInotify, badge: "experimental") {
                                Toggle("", isOn: $m.draft.mountInotify).labelsHidden().toggleStyle(.switch).tint(Theme.accent)
                            }
                            FormRow("Fixed DNS resolvers", flag: "--dns", help: ("DNS resolvers", "By default the VM copies DNS from your Mac, which can break after switching Wi-Fi or joining a VPN. Fixed resolvers keep containers online."), changed: m.draft.dns != m.saved.dns) {
                                HStack(spacing: 8) {
                                    if !m.draft.dns.isEmpty { ForEach(m.draft.dns, id: \.self) { Text($0).font(.system(size: 11.5, design: .monospaced)).padding(.horizontal, 6).padding(.vertical, 2).background(Theme.fill, in: RoundedRectangle(cornerRadius: 5)) } }
                                    Toggle("", isOn: Binding(get: { !m.draft.dns.isEmpty }, set: { m.draft.dns = $0 ? ["1.1.1.1", "8.8.8.8"] : [] })).labelsHidden().toggleStyle(.switch).tint(Theme.accent)
                                }
                            }
                            FormRow("Kubernetes", flag: "--kubernetes", help: ("Kubernetes", "Runs a small k3s cluster in the VM. It costs memory and CPU all the time, so turn it on only when you use it."), changed: m.draft.kubernetes != m.saved.kubernetes) {
                                Toggle("", isOn: $m.draft.kubernetes).labelsHidden().toggleStyle(.switch).tint(Theme.accent)
                            }
                        }
                        DisclosureGroup(isExpanded: $showAdvanced) {
                            VStack(spacing: 0) {
                                FormRow("Reachable VM address", flag: "--network-address", help: ("VM address", "Gives the VM its own IP so you can reach containers from other devices on your network."), changed: m.draft.networkAddress != m.saved.networkAddress) { Toggle("", isOn: $m.draft.networkAddress).labelsHidden().toggleStyle(.switch).tint(Theme.accent) }
                                FormRow("Forward SSH agent", flag: "--ssh-agent", help: ("SSH agent", "Lets processes in the VM use your Mac's SSH keys, for example to clone private repos."), changed: m.draft.sshAgent != m.saved.sshAgent) { Toggle("", isOn: $m.draft.sshAgent).labelsHidden().toggleStyle(.switch).tint(Theme.accent) }
                                FormRow("Nested virtualization", flag: "--nested-virtualization", help: ("Nested virtualization", "Allows running VMs inside the VM. Needs an M3 or newer chip."), changed: m.draft.nestedVirtualization != m.saved.nestedVirtualization) { Toggle("", isOn: $m.draft.nestedVirtualization).labelsHidden().toggleStyle(.switch).tint(Theme.accent) }
                                FormRow("Hostname", flag: "--hostname", help: ("Hostname", "Custom name for the VM."), changed: m.draft.hostname != m.saved.hostname) { TextField("colima", text: $m.draft.hostname).textFieldStyle(.roundedBorder).frame(width: 160) }
                            }.padding(.horizontal, 14).background(Theme.card, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline)).padding(.top, 8)
                        } label: { Text("Advanced").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.accent) + Text("  network address, SSH agent, nested virtualization, hostname").font(.system(size: 12)).foregroundStyle(.secondary) }
                    }.padding(.vertical, 14).padding(.leading, 22)
                }
                sidePanel.frame(width: 290).padding(.trailing, 22).padding(.top, 14)
            }
            actionBar
        }
    }

    private var recommendationBanner: some View {
        let r = model.recommendation, hw = model.hardware
        let matches = model.draft.cpus == r.cpus && model.draft.memoryGiB == r.memoryGiB
        return HStack(spacing: 12) {
            Image(systemName: "wand.and.stars").foregroundStyle(Theme.accent)
            Text("**Recommended for this Mac** (\(hw.totalCores) cores · \(Int(hw.memoryGiB)) GB): \(r.cpus) CPU · \(Int(r.memoryGiB)) GB RAM · \(r.diskGiB) GB disk. About half your cores and 50% of RAM, so macOS keeps the rest.").font(.system(size: 12.5))
            Spacer(minLength: 0)
            Button(matches ? "Applied" : "Use these") { model.draft.cpus = r.cpus; model.draft.memoryGiB = r.memoryGiB; if !locked { model.draft.diskGiB = r.diskGiB } }.buttonStyle(Pill(kind: .primary)).disabled(matches)
        }.padding(11).background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: Side panel: impact, command, advice

    private var sidePanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("What this takes from your Mac")
                    VStack(alignment: .leading, spacing: 12) {
                        split("Memory", total: "\(Int(model.hardware.memoryGiB)) GB total", fraction: model.draft.memoryGiB / model.hardware.memoryGiB, left: "Colima \(Int(model.draft.memoryGiB)) GB", right: "macOS keeps \(Int(max(0, model.hardware.memoryGiB - model.draft.memoryGiB))) GB", over: model.draft.memoryGiB > model.hardware.memoryGiB * 0.6)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text("CPU cores").font(.system(size: 12, weight: .semibold)); Spacer(); Text("\(model.hardware.performanceCores) performance + \(model.hardware.totalCores - model.hardware.performanceCores) efficiency").font(.system(size: 11)).foregroundStyle(.secondary) }
                            HStack(spacing: 3) { ForEach(0..<model.hardware.totalCores, id: \.self) { i in RoundedRectangle(cornerRadius: 3).fill(i < model.draft.cpus ? Theme.accent : Theme.fill).frame(height: 14) } }
                            Text("\(model.draft.cpus) for Colima").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.accent)
                        }
                    }.card()
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack { SectionLabel("Equivalent command"); Spacer(); CopyButton(text: model.draft.commandLine(profile: model.selected), label: "Copy command") }
                    Text(model.draft.commandLine(profile: model.selected).replacingOccurrences(of: " --", with: "\n  --")).font(.system(size: 11, design: .monospaced)).foregroundStyle(Color(white: 0.85)).frame(maxWidth: .infinity, alignment: .leading).padding(11).background(Theme.terminal, in: RoundedRectangle(cornerRadius: 10)).textSelection(.enabled)
                }
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Optimize")
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(model.advice.sorted { rank($0) < rank($1) }) { a in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: a.severity == .good ? "checkmark.circle.fill" : a.severity == .warning ? "exclamationmark.triangle.fill" : "lightbulb.fill").foregroundStyle(a.severity == .good ? Theme.ok : Theme.warn).font(.system(size: 12)).padding(.top, 2)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(a.title).font(.system(size: 12.5, weight: .semibold))
                                    Text(a.detail).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                    if a.effect != .none { Badge(text: a.effect == .recreate ? "needs recreate" : "needs restart", kind: a.effect == .recreate ? .danger : .warn) }
                                }
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).card()
                }
            }.padding(.bottom, 14)
        }
    }

    private func rank(_ a: Advice) -> Int { a.severity == .warning ? 0 : a.severity == .suggestion ? 1 : 2 }

    private func split(_ title: String, total: String, fraction: Double, left: String, right: String, over: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack { Text(title).font(.system(size: 12, weight: .semibold)); Spacer(); Text(total).font(.system(size: 11)).foregroundStyle(.secondary) }
            UsageBar(fraction: fraction, tint: over ? Theme.warn : Theme.accent, height: 14)
            HStack { Text(left).font(.system(size: 11.5, weight: .medium)).foregroundStyle(over ? Theme.warn : Theme.accent); Spacer(); Text(right).font(.system(size: 11.5)).foregroundStyle(.secondary) }
        }
    }

    // MARK: Action bar

    private var actionBar: some View {
        HStack(spacing: 12) {
            if model.hasPendingChanges {
                (Text("\(model.recreateReasons.count + (model.restartPending ? 1 : 0)) pending changes").bold() + Text(model.restartPending ? " · restart applies resources and network" : "") + Text(model.recreateReasons.isEmpty ? "" : " · \(model.recreateReasons.map { $0 == .vmType ? "VM type" : $0 == .mountType ? "mount type" : $0 == .arch ? "architecture" : "runtime" }.joined(separator: ", ")): recreate VM"))
                    .font(.system(size: 12.5)).lineLimit(2)
            } else { Text("No pending changes").font(.system(size: 12.5)).foregroundStyle(.secondary) }
            Spacer()
            Button("Discard") { model.draft = model.saved }.buttonStyle(.plain).foregroundStyle(.secondary).disabled(!model.hasPendingChanges)
            if model.profile == nil {
                Button("Create & start") { model.createProfile(name: model.selected, config: model.draft) }.buttonStyle(Pill(kind: .primary))
            } else {
                Button("Apply & Restart") { model.applyAndRestart() }.buttonStyle(Pill()).disabled(!model.restartPending || model.busy)
                Button("Recreate VM…") { model.sheet = .recreate }.buttonStyle(Pill(kind: .danger)).disabled(model.recreateReasons.isEmpty || model.busy)
            }
        }.padding(.horizontal, 22).padding(.vertical, 10).background(Theme.sidebar.opacity(0.7)).overlay(alignment: .top) { Divider() }
    }

    // MARK: YAML tab

    private var yaml: some View {
        let url = ColimaConfig.configURL(profile: model.selected)
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? "No colima.yaml yet for this profile."
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                CopyButton(text: url.path, label: "Copy path")
                Spacer()
                Button("Open in editor") { NSWorkspace.shared.open(url) }.buttonStyle(Pill())
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }.buttonStyle(Pill())
            }
            Text("This file is Colima's own configuration. Keep it in your dotfiles to get the same setup on a new Mac with one file.").font(.system(size: 12)).foregroundStyle(.secondary)
            ScrollView { Text(text).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Color(white: 0.88)).frame(maxWidth: .infinity, alignment: .leading).padding(12).textSelection(.enabled) }
                .background(Theme.terminal, in: RoundedRectangle(cornerRadius: 10))
        }.padding(22)
    }

    private func group<C: View>(_ title: String, _ sub: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) { SectionLabel(title); Text("· \(sub)").font(.system(size: 11)).foregroundStyle(.secondary) }.padding(.leading, 4)
            VStack(spacing: 0) { content() }.padding(.horizontal, 14).background(Theme.card, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline))
        }
    }
}

struct FormRow<Control: View>: View {
    let title: String
    let flag: String
    let help: (String, String)
    var lock: String?
    var changed = false
    var note: String?
    var badge: String?
    @ViewBuilder var control: Control
    init(_ title: String, flag: String, help: (String, String), lock: String? = nil, changed: Bool = false, note: String? = nil, badge: String? = nil, @ViewBuilder _ control: () -> Control) {
        self.title = title; self.flag = flag; self.help = help; self.lock = lock; self.changed = changed; self.note = note; self.badge = badge; self.control = control()
    }
    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 13)).fixedSize()
                HelpTip(title: help.0, text: help.1)
                Text(flag).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).layoutPriority(-1)
                if changed { Circle().fill(Color.orange).frame(width: 7, height: 7).accessibilityLabel("changed") }
                if let n = note { Text(n).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize() }
                if let l = lock { Label(l, systemImage: "lock.fill").font(.system(size: 10.5, weight: .semibold)).labelStyle(.titleAndIcon).fixedSize().padding(.horizontal, 6).padding(.vertical, 1).background(Theme.fill, in: Capsule()).foregroundStyle(.secondary) }
                if let b = badge { Badge(text: b, kind: b == "experimental" ? .warn : .accent) }
            }
            Spacer(minLength: 8)
            control.fixedSize()
        }.padding(.vertical, 8).overlay(alignment: .top) { Divider().opacity(0.6) }
    }
}

struct SliderField: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let label: String
    var body: some View {
        HStack(spacing: 12) {
            Slider(value: Binding(get: { value }, set: { value = ($0 / step).rounded() * step }), in: range).tint(Theme.accent).frame(width: 150)
            Text(label).font(.system(size: 13, weight: .semibold)).frame(minWidth: 62, alignment: .trailing)
        }
    }
}

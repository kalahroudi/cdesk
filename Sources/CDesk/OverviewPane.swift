// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 kalahroudi

import SwiftUI
import ColimaKit

struct OverviewPane: View {
    let model = AppModel.shared

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: "Overview · \(model.selected)", subtitle: model.updatedAt.map { "Updated \($0.formatted(date: .omitted, time: .standard))" }) {
                HStack(spacing: 8) {
                    if model.profiles.count > 1 {
                        Menu(model.selected) { ForEach(model.profiles) { p in Button(p.name) { model.select(profile: p.name) } } }.fixedSize()
                    }
                    if model.isRunning {
                        Button("Restart") { model.restartColima() }.buttonStyle(Pill()).disabled(model.busy)
                        Button("Stop") { model.stopColima() }.buttonStyle(Pill()).disabled(model.busy)
                    } else {
                        Button("Start") { model.startColima() }.buttonStyle(Pill(kind: .primary)).disabled(model.busy || model.profile == nil)
                    }
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.profile == nil { NoProfileCard() }
                    architecture
                    if model.isRunning { usage }
                    cleanupCard
                }.padding(22)
            }
        }
    }

    // MARK: How it fits together

    private var architecture: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { SectionLabel("How it fits together"); HelpTip(title: "Colima, Lima and Docker", text: "Docker needs Linux, which macOS doesn't have. Colima starts a small Linux VM (using Lima) and runs the Docker daemon inside it. Your docker command on the Mac talks to that daemon through a socket.") ; Spacer(); Text("Tap a ? to learn what a box is").font(.system(size: 11.5)).foregroundStyle(.secondary) }
            HStack(alignment: .center, spacing: 0) {
                box("YOUR MAC · macOS", tint: .secondary, border: Theme.hairline.opacity(2)) {
                    node("Docker CLI", "docker, compose", help: ("Docker CLI", "The docker command you type. It sends requests to the daemon inside the VM."))
                    node("Project files", "~/projects", help: ("Project files", "Folders on your Mac. Colima mounts them into the VM so containers can read and write them."))
                }.frame(maxWidth: .infinity)
                VStack(spacing: 26) {
                    arrow("Unix socket", "docker context")
                    arrow("\(model.saved.mountType.rawValue) mount", "file sync")
                }.frame(width: 110)
                box("COLIMA VM · Linux · Lima", tint: Theme.accent, border: Theme.accent) {
                    HStack { Badge(text: model.saved.vmType.rawValue.uppercased(), kind: .accent); if let p = model.profile { Badge(text: "\(p.cpus) CPU", kind: .accent); Badge(text: "\(Int(p.memoryGiB)) GB", kind: .accent) } }
                    node("Docker daemon", model.profile?.isRunning == true ? "running" : "stopped", help: ("Docker daemon", "dockerd runs here, inside the VM, and starts your containers."))
                    FlowLayout(spacing: 6) {
                        ForEach(model.containers.prefix(5)) { c in Text(c.name).font(.system(size: 11.5)).padding(.horizontal, 9).padding(.vertical, 5).background(Theme.card, in: RoundedRectangle(cornerRadius: 7)).overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.accent.opacity(0.4))) }
                        if model.containers.count > 5 { Text("+ \(model.containers.count - 5) more").font(.system(size: 11.5)).foregroundStyle(.secondary).padding(.horizontal, 9).padding(.vertical, 5) }
                        if model.containers.isEmpty { Text("No containers yet").font(.system(size: 11.5)).foregroundStyle(.secondary) }
                    }
                }.frame(maxWidth: .infinity)
            }
        }.card(padding: 14)
    }

    private func box<C: View>(_ title: String, tint: Color, border: Color, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(title).font(.system(size: 11, weight: .semibold)).tracking(0.4).foregroundStyle(tint); content() }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Theme.pane.opacity(0.6), in: RoundedRectangle(cornerRadius: 11)).overlay(RoundedRectangle(cornerRadius: 11).stroke(border, lineWidth: 1.5))
    }

    private func node(_ title: String, _ sub: String, help: (String, String)) -> some View {
        HStack(spacing: 6) {
            VStack(spacing: 1) { Text(title).font(.system(size: 12, weight: .semibold)); Text(sub).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary) }
            HelpTip(title: help.0, text: help.1)
        }.frame(maxWidth: .infinity).padding(8).background(Theme.fill, in: RoundedRectangle(cornerRadius: 9))
    }

    private func arrow(_ top: String, _ sub: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: "arrow.left.and.right").foregroundStyle(Theme.accent)
            Text(top).font(.system(size: 10.5, weight: .medium)); Text(sub).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
        }
    }

    // MARK: Usage

    private var usage: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Usage · last \(model.history.count * max(2, model.settings.refreshSeconds) / 60 + 1) min")
            HStack(spacing: 12) {
                chart("CPU", "\(String(format: "%.1f", model.totalCPUPercent))% of \(model.profile?.cpus ?? 0) cores", model.history.map(\.cpu))
                chart("Memory", "\(String(format: "%.1f", model.usedMemoryGiB ?? 0)) of \(Int(model.profile?.memoryGiB ?? 0)) GB", model.history.map(\.memGiB))
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text("Disk").font(.system(size: 12)).foregroundStyle(.secondary); Spacer(); Text("\(formatBytes(model.inventory?.usage.reduce(0) { $0 + parseSize($1.size) } ?? 0)) of \(Int(model.profile?.diskGiB ?? 0)) GB").font(.system(size: 12, weight: .semibold)) }
                    UsageBar(fraction: Double(model.inventory?.usage.reduce(0) { $0 + parseSize($1.size) } ?? 0) / max((model.profile?.diskGiB ?? 1) * 1_000_000_000, 1), height: 8)
                    Text("Disk only grows. Reclaim space in Cleanup.").font(.system(size: 11)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).card()
            }
        }
    }

    private func chart(_ title: String, _ value: String, _ values: [Double]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text(title).font(.system(size: 12)).foregroundStyle(.secondary); Spacer(); Text(value).font(.system(size: 12, weight: .semibold)) }
            Sparkline(values: values).frame(height: 56)
        }.frame(maxWidth: .infinity).card()
    }

    // MARK: Cleanup teaser

    @ViewBuilder private var cleanupCard: some View {
        if model.isRunning, let inv = model.inventory {
            let rec = inv.reclaimableBytes
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Text(rec > 0 ? "\(formatBytes(rec)) can be reclaimed" : "Nothing to reclaim").font(.system(size: 13.5, weight: .semibold)); HelpTip(title: "Reclaimable", text: "Space used by images, containers, volumes and build cache that nothing is using right now. Removing it is safe, except volumes, which hold data.") }
                    GeometryReader { g in
                        let total = max(Double(rec), 1)
                        HStack(spacing: 0) { ForEach(Array(inv.usage.enumerated()), id: \.offset) { i, u in Rectangle().fill(Theme.accent.opacity(1 - Double(i) * 0.22)).frame(width: g.size.width * Double(u.reclaimableBytes) / total) } }.clipShape(RoundedRectangle(cornerRadius: 5))
                    }.frame(height: 14)
                    HStack(spacing: 14) { ForEach(inv.usage.filter { $0.reclaimableBytes > 0 }) { u in Text("**\(formatBytes(u.reclaimableBytes))** \(u.type.lowercased())").font(.system(size: 11.5)).foregroundStyle(.secondary) } }
                }
                Button("Review & clean up…") { Nav.shared.section = .cleanup }.buttonStyle(Pill(kind: .primary))
            }.card(padding: 14)
        }
    }
}

struct NoProfileCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No Colima profile yet").font(.system(size: 15, weight: .semibold))
            Text("Create one to start running containers. The recommended settings for this Mac are filled in for you.").font(.system(size: 13)).foregroundStyle(.secondary)
            Button("Create default profile…") { AppModel.shared.sheet = .newProfile }.buttonStyle(Pill(kind: .primary))
        }.frame(maxWidth: .infinity, alignment: .leading).card(padding: 16)
    }
}

/// Wraps children onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width ?? 400).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (i, f) in arrange(subviews, width: bounds.width).frames.enumerated() { subviews[i].place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY), proposal: ProposedViewSize(f.size)) }
    }
    private func arrange(_ subviews: Subviews, width: CGFloat) -> (frames: [CGRect], size: CGSize) {
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, frames: [CGRect] = [], maxX: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > width, x > 0 { x = 0; y += row + spacing; row = 0 }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: sz)); x += sz.width + spacing; row = max(row, sz.height); maxX = max(maxX, x)
        }
        return (frames, CGSize(width: maxX, height: y + row))
    }
}

// MARK: Cleanup

struct CleanupPane: View {
    let model = AppModel.shared
    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: "Cleanup", subtitle: "Reclaim disk space inside the VM. The VM disk itself only grows, so cleaning up keeps it from filling.")
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let inv = model.inventory {
                        HStack(alignment: .firstTextBaseline, spacing: 8) { Text(formatBytes(inv.reclaimableBytes)).font(.system(size: 30, weight: .semibold)); Text("reclaimable now").foregroundStyle(.secondary) }
                        VStack(spacing: 0) {
                            ForEach(inv.usage) { u in
                                HStack(spacing: 14) {
                                    VStack(alignment: .leading, spacing: 2) { Text(u.type).font(.system(size: 13, weight: .medium)); Text("\(u.active) of \(u.total) in use").font(.system(size: 11.5)).foregroundStyle(.secondary) }.frame(width: 150, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 4) {
                                        UsageBar(fraction: parseSize(u.size) > 0 ? 1 - Double(u.reclaimableBytes) / Double(parseSize(u.size)) : 0, height: 7)
                                        Text("\(u.size) total · \(u.reclaimable) reclaimable").font(.system(size: 11.5)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    cleanButtons(u.type)
                                }.padding(.vertical, 10)
                                if u.id != inv.usage.last?.id { Divider() }
                            }
                        }.padding(.horizontal, 14).background(Theme.card, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline))
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle").foregroundStyle(.secondary)
                            Text("Volumes hold data such as databases. Removing unused volumes asks you to type the profile name first. Everything else can be pulled or rebuilt.").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    } else if model.isRunning { SkeletonList(rows: 5) } else { Text("Start Colima to see disk usage.").foregroundStyle(.secondary) }
                }.padding(22)
            }
        }
    }

    @ViewBuilder private func cleanButtons(_ type: String) -> some View {
        switch type {
        case "Images": HStack { Button("Dangling") { model.sheet = .prune(.danglingImages) }.buttonStyle(Pill()); Button("All unused") { model.sheet = .prune(.unusedImages) }.buttonStyle(Pill()) }
        case "Containers": Button("Remove stopped") { model.sheet = .prune(.stoppedContainers) }.buttonStyle(Pill())
        case "Local Volumes": Button("Remove unused…") { model.sheet = .prune(.unusedVolumes) }.buttonStyle(Pill(kind: .danger))
        case "Build Cache": Button("Clear") { model.sheet = .prune(.buildCache) }.buttonStyle(Pill())
        default: EmptyView()
        }
    }
}

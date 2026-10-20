// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 kalahroudi

import SwiftUI
import ColimaKit

/// The Manager window: a fixed sidebar (collapsible to icons) and a main pane that uses the full width.
/// Actions open a right-side sheet and close it when done, so results show up without any navigation.
struct ManagerView: View {
    var stacksTab = false
    let model = AppModel.shared
    let nav = Nav.shared
    let prefs = Prefs.shared

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
            Divider()
            ZStack {
                Theme.pane
                VStack(spacing: 0) {
                    if let t = model.runningTask { TaskBanner(task: t) }
                    detail
                }
                SheetHost()
            }
            .overlay(alignment: .bottom) { ToastView().padding(.bottom, 6) }
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 900, minHeight: 600)
        .onAppear { model.setManagerVisible(true); Task { await model.refresh(forceInventory: true) } }
    }

    @ViewBuilder private var detail: some View {
        if !model.loadedOnce {
            SkeletonList(rows: 9).frame(maxHeight: .infinity, alignment: .top).padding(.top, 40)   // never show a half-loaded page
        } else if model.needsSetup && nav.section != .settings && nav.section != .help {
            SetupView().padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).padding(.top, 40)
        } else {
            switch nav.section {
            case .overview: OverviewPane()
            case .profiles: ProfilesPane()
            case .containers: ContainersPane(initialTab: stacksTab ? .stacks : .containers)
            case .images: ImagesPane()
            case .cleanup: CleanupPane()
            case .settings: SettingsPane()
            case .help: HelpPane()
            }
        }
    }
}

struct Sidebar: View {
    let model = AppModel.shared
    let nav = Nav.shared
    let prefs = Prefs.shared
    var collapsed: Bool { prefs.sidebarCollapsed }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Spacer()
                Button { withAnimation(.easeInOut(duration: 0.18)) { prefs.sidebarCollapsed.toggle() } } label: {
                    Image(systemName: "sidebar.left").foregroundStyle(.secondary)
                }.buttonStyle(.plain).help(collapsed ? "Expand sidebar" : "Collapse to icons").accessibilityLabel(collapsed ? "Expand sidebar" : "Collapse sidebar")
            }.padding(.top, 14).padding(.bottom, 12).padding(.horizontal, collapsed ? 0 : 6)
            ForEach([Section.overview, .profiles, .containers, .images, .cleanup]) { item($0) }
            Spacer()
            ForEach([Section.settings, .help]) { item($0) }
            if !collapsed {
                Text("App memory \(AppMemory.footprint)").font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.top, 8)
            }
        }
        .padding(.horizontal, 10).padding(.bottom, 12)
        .padding(.top, 20)   // room for the traffic lights
        .frame(width: collapsed ? 62 : 200)
        .background(Theme.sidebar)
    }

    private func item(_ s: Section) -> some View {
        let on = nav.section == s
        return Button { nav.section = s } label: {
            HStack(spacing: 9) {
                Image(systemName: s.symbol).font(.system(size: 14)).frame(width: 20)
                if !collapsed {
                    Text(s.title).font(.system(size: 13, weight: on ? .semibold : .regular)).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 4)
                    badge(s)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: collapsed ? .center : .leading)
            .foregroundStyle(on ? Theme.accent : Color.primary.opacity(0.85))
            .background(on ? Theme.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain).help(s.title).accessibilityLabel(s.title)
    }

    @ViewBuilder private func badge(_ s: Section) -> some View {
        switch s {
        case .profiles: Text("\(model.profiles.count)").font(.system(size: 11)).foregroundStyle(.secondary)
        case .containers: Text("\(model.containers.count)").font(.system(size: 11)).foregroundStyle(.secondary)
        case .cleanup:
            if let inv = model.inventory, inv.reclaimableBytes > 500_000_000 {
                Text(shortSize(inv.reclaimableBytes)).font(.system(size: 10.5, weight: .semibold)).lineLimit(1).fixedSize().foregroundStyle(.white).padding(.horizontal, 6).background(Theme.danger.opacity(0.9), in: Capsule())
            }
        case .settings:
            if Updater.shared.available != nil { Circle().fill(Theme.accent).frame(width: 7, height: 7) }
        default: EmptyView()
        }
    }
}

/// Compact size for badges: "13 GB", "800 MB".
func shortSize(_ bytes: Int64) -> String {
    bytes >= 1_000_000_000 ? "\(Int((Double(bytes) / 1e9).rounded())) GB" : "\(max(1, Int((Double(bytes) / 1e6).rounded()))) MB"
}

/// Resident memory of this app, shown in the sidebar so the "light" claim is visible.
enum AppMemory {
    static var footprint: String {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) } }
        return kr == KERN_SUCCESS ? "\(Int(info.phys_footprint / 1_048_576)) MB" : "–"
    }
}

struct TaskBanner: View {
    let task: BackgroundTask
    @State private var open = false
    var body: some View {
        VStack(spacing: 0) {
            Button { open.toggle() } label: {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(task.title).font(.system(size: 12.5, weight: .medium))
                    Text(task.lines.last ?? "").font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: 10)).foregroundStyle(.secondary)
                }.padding(.horizontal, 22).padding(.vertical, 7).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if open {
                ScrollView { Text(task.lines.suffix(60).joined(separator: "\n")).font(.system(size: 11, design: .monospaced)).foregroundStyle(.white.opacity(0.85)).frame(maxWidth: .infinity, alignment: .leading).padding(10) }
                    .frame(height: 140).background(Theme.terminal)
            }
        }.background(Theme.accentSoft)
    }
}

// MARK: Pane scaffolding

/// Title, optional subtitle, trailing controls, then optional tabs. Used by every pane so they all look the same.
struct PaneHeader<Trailing: View, Tabs: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var tabs: Tabs
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 19, weight: .semibold))
                    if let s = subtitle { Text(s).font(.system(size: 12)).foregroundStyle(.secondary) }
                }
                Spacer()
                trailing
            }
            tabs
        }
        .padding(.horizontal, 22).padding(.top, 38).padding(.bottom, Tabs.self == EmptyView.self ? 12 : 0)
        .background(Theme.pane)
        .overlay(alignment: .bottom) { Divider() }
    }
}

extension PaneHeader where Tabs == EmptyView {
    init(title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) { self.init(title: title, subtitle: subtitle, trailing: trailing, tabs: { EmptyView() }) }
}
extension PaneHeader where Trailing == EmptyView, Tabs == EmptyView {
    init(title: String, subtitle: String? = nil) { self.init(title: title, subtitle: subtitle, trailing: { EmptyView() }, tabs: { EmptyView() }) }
}

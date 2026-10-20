// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 kalahroudi

import SwiftUI
import AppKit
import ColimaKit

struct SettingsPane: View {
    let prefs = Prefs.shared
    @State private var tab: Tab
    enum Tab: Hashable { case general, terminal, updates, agents, about }
    init(initialTab: Tab = .general) { _tab = State(initialValue: initialTab) }

    var body: some View {
        @Bindable var p = prefs
        VStack(spacing: 0) {
            PaneHeader(title: "Settings") {
                EmptyView()
            } tabs: {
                TabBar(tabs: [(Tab.general, "General"), (Tab.terminal, "Terminal & Docker"), (Tab.updates, "Updates"), (Tab.agents, "Agents (MCP)"), (Tab.about, "About")], selection: $tab)
            }
            ScrollView {
                Group {
                    switch tab {
                    case .general: general
                    case .terminal: terminal
                    case .updates: UpdatesView()
                    case .agents: AgentsView()
                    case .about: about
                    }
                }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack { Text("Colima Manager \(BuildInfo.current.version) · Apache-2.0 · github.com/kalahroudi/cdesk"); Spacer(); Text("Settings save automatically") }.font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 22).padding(.vertical, 8)
        }
    }

    private var general: some View {
        @Bindable var p = prefs
        return HStack(alignment: .top, spacing: 18) {
            VStack(spacing: 18) {
                SettingsGroup("Startup") {
                    SettingRow("Launch at login", "Adds the app to Login Items. Turn it off any time.", error: prefs.launchAtLoginError) { Toggle("", isOn: Binding(get: { prefs.launchAtLogin }, set: { prefs.setLaunchAtLogin($0) })).labelsHidden().toggleStyle(.switch).tint(Theme.accent) }
                    SettingRow("Start Colima when the app opens", "Starts the profile you last used.") { Toggle("", isOn: $p.autoStartColima).labelsHidden().toggleStyle(.switch).tint(Theme.accent) }
                    SettingRow("Stop Colima when quitting", "Frees the VM's memory. Containers stop too.") { Toggle("", isOn: $p.stopOnQuit).labelsHidden().toggleStyle(.switch).tint(Theme.accent) }
                }
                SettingsGroup("Appearance") {
                    SettingRow("Theme", nil) { Segmented(options: ThemeChoice.allCases.map { ($0, $0.label) }, selection: $p.theme) }
                    SettingRow("Dock icon", "Keep the app in the Dock as well as the menu bar.") { Toggle("", isOn: $p.showDockIcon).labelsHidden().toggleStyle(.switch).tint(Theme.accent) }
                }
            }.frame(maxWidth: .infinity)
            VStack(spacing: 18) {
                SettingsGroup("Performance") {
                    SettingRow("Refresh only when visible", "Nothing is polled while the popover and window are closed. An idle app uses almost no CPU.") { Badge(text: "always on", kind: .ok) }
                    SettingRow("Refresh interval", nil) { Segmented(options: [(2, "2 s"), (5, "5 s"), (15, "15 s")], selection: $p.refreshSeconds) }
                }
                SettingsGroup("Notifications") {
                    SettingRow("Notify when long tasks finish", "Starting, recreating, pulling and cleaning run in the background.") { Toggle("", isOn: $p.notify).labelsHidden().toggleStyle(.switch).tint(Theme.accent) }
                }
            }.frame(maxWidth: .infinity)
        }
    }

    private var terminal: some View {
        @Bindable var p = prefs
        return HStack(alignment: .top, spacing: 18) {
            SettingsGroup("Shell access") {
                SettingRow("Open shells in", "cdesk hands off to your terminal app instead of embedding one, which keeps it light.") { Picker("", selection: $p.terminal) { ForEach(TerminalApp.allCases, id: \.self) { Text($0.rawValue) } }.labelsHidden().fixedSize() }
                SettingRow("Shell to try first", "Falls back to sh when the image has no bash.") { Segmented(options: ShellChoice.allCases.map { ($0, $0.rawValue) }, selection: $p.shell) }
            }.frame(maxWidth: .infinity)
            SettingsGroup("Docker") {
                SettingRow("Switch Docker context with the profile", "Runs docker context use colima-<profile> when you start a profile.") { Toggle("", isOn: $p.switchDockerContext).labelsHidden().toggleStyle(.switch).tint(Theme.accent) }
            }.frame(maxWidth: .infinity)
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(nsImage: AppIcon.image(size: 72)).resizable().frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Colima Manager").font(.system(size: 18, weight: .semibold))
                    Text("Version \(BuildInfo.current.version) · \(BuildInfo.current.shortCommit)").foregroundStyle(.secondary)
                    Text("A light menu bar and Dock app for Colima and Docker.").font(.system(size: 12.5))
                }
            }
            HStack(spacing: 10) {
                Link("Source on GitHub", destination: URL(string: "https://github.com/kalahroudi/cdesk")!)
                Link("Documentation", destination: URL(string: "https://kalahroudi.github.io/cdesk/")!)
                Link("Report an issue", destination: URL(string: "https://github.com/kalahroudi/cdesk/issues")!)
            }.font(.system(size: 13))
            Text("Apache License 2.0. Colima is © its authors and is not affiliated with this project.").font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}

struct SettingsGroup<C: View>: View {
    let title: String
    @ViewBuilder var content: C
    init(_ t: String, @ViewBuilder content: () -> C) { title = t; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(title).padding(.leading, 4)
            VStack(spacing: 0) { content }.padding(.horizontal, 14).background(Theme.card, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline))
        }
    }
}

struct SettingRow<Control: View>: View {
    let title: String
    let detail: String?
    var error: String?
    @ViewBuilder var control: Control
    init(_ title: String, _ detail: String?, error: String? = nil, @ViewBuilder _ control: () -> Control) { self.title = title; self.detail = detail; self.error = error; self.control = control() }
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                if let d = detail { Text(d).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                if let e = error { Text(e).font(.system(size: 11.5)).foregroundStyle(Theme.danger) }
            }
            Spacer(minLength: 8)
            control
        }.padding(.vertical, 10).overlay(alignment: .top) { Divider().opacity(0.6) }
    }
}

// MARK: Updates

struct UpdatesView: View {
    let u = Updater.shared
    let prefs = Prefs.shared

    var body: some View {
        @Bindable var p = prefs
        VStack(alignment: .leading, spacing: 16) {
            SettingsGroup("This build") {
                SettingRow("Version", "From \(u.build.repo) · branch \(u.build.branch)") { Text("\(u.build.version) · \(u.build.shortCommit)\(u.build.isDirty ? " (modified)" : "")").font(.system(size: 12.5, design: .monospaced)) }
                SettingRow("Update channel", "Releases: signed disk images, the safe default. Main branch: also offers a build of the newest commit (needs Xcode command line tools).") { Segmented(options: UpdateChannel.allCases.map { ($0, $0.label) }, selection: $p.updateChannel) }
                SettingRow("Check automatically", "Once a day at most, when the app starts. Nothing runs in between.") { Toggle("", isOn: $p.autoCheckUpdates).labelsHidden().toggleStyle(.switch).tint(Theme.accent) }
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    statusLine
                    Spacer()
                    Button(u.phase == .checking ? "Checking…" : "Check for updates") { Task { await u.check() } }.buttonStyle(Pill()).disabled(u.busy)
                    if let info = u.available { Button(info.release != nil ? "Install \(info.label)" : "Build & install \(info.label)") { Task { await u.install() } }.buttonStyle(Pill(kind: .primary)).disabled(u.busy) }
                }
                if case .working(let step) = u.phase {
                    VStack(alignment: .leading, spacing: 6) {
                        if let pr = u.progress { ProgressView(value: pr) } else { ProgressView().controlSize(.small) }
                        Text(step).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                if case .failed(let m) = u.phase { Label(m, systemImage: "exclamationmark.triangle.fill").font(.system(size: 12.5)).foregroundStyle(Theme.danger) }
                if let n = u.notice { Label(n, systemImage: "arrow.uturn.backward.circle").font(.system(size: 12.5)).foregroundStyle(Theme.warn) }
                if let info = u.available, !info.summaries.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionLabel(info.release != nil ? "What's new in \(info.label)" : "\(info.aheadBy) new commit\(info.aheadBy == 1 ? "" : "s") on \(u.build.branch)")
                        ForEach(info.summaries, id: \.self) { Text("• \($0)").font(.system(size: 12.5)) }
                    }.padding(.top, 4)
                }
            }.card(padding: 14)
            Text("Releases install a signed disk image: it is downloaded, checked against its SHA-256, verified, swapped in after the app quits, and rolled back automatically if the new version doesn't start. Without a release, the app can build the newest commit of \(u.build.branch) (needs Xcode command line tools).").font(.system(size: 12)).foregroundStyle(.secondary)
            if !u.log.isEmpty || !u.savedLog.isEmpty {
                DisclosureGroup("Update log") {
                    ScrollView { Text((u.log.isEmpty ? u.savedLog : u.log).suffix(80).joined(separator: "\n")).font(.system(size: 11, design: .monospaced)).foregroundStyle(Color(white: 0.85)).frame(maxWidth: .infinity, alignment: .leading).padding(10).textSelection(.enabled) }
                        .frame(height: 150).background(Theme.terminal, in: RoundedRectangle(cornerRadius: 8))
                }.font(.system(size: 12.5))
            }
        }.frame(maxWidth: 720)
    }

    @ViewBuilder private var statusLine: some View {
        switch u.status {
        case .upToDate?: Label("You're up to date", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.ok)
        case .available(let i)?: Label("\(i.label) is available", systemImage: "arrow.down.circle.fill").foregroundStyle(Theme.accent)
        case .notComparable(let why)?: Label(why, systemImage: "info.circle").foregroundStyle(.secondary)
        case nil: Text(u.isBundled ? "Not checked yet" : "Updates work from the installed app, not a development build.").foregroundStyle(.secondary)
        }
    }
}

// MARK: Agents

/// Finds AI agents on this Mac and connects them to the cdesk MCP server with one click.
struct AgentsView: View {
    @State private var statuses: [AgentStatus] = []
    @State private var busy: AgentKind?
    @State private var restartHint: AgentKind?
    @State private var error: String?
    @State private var manual = false
    private let server = AgentIntegrations.serverPath()
    private var serverMissing: Bool { !FileManager.default.isExecutableFile(atPath: server) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Let an AI agent run Colima for you").font(.system(size: 15, weight: .semibold))
                    Text("Agents can start and stop the VM, manage containers, stacks, images and volumes, read logs and run commands in containers. Destructive tools need an explicit confirmation.").font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Button("Rescan") { scan() }.buttonStyle(Pill())
            }
            if serverMissing {
                Label("The MCP server was not found at \(server). Move CDesk into Applications to connect agents.", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12.5)).padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Theme.warnSoft, in: RoundedRectangle(cornerRadius: 9))
            }
            VStack(spacing: 0) {
                ForEach(statuses) { st in
                    row(st)
                    if st.id != statuses.last?.id { Divider() }
                }
                if statuses.isEmpty { SkeletonList(rows: 3) }
            }.padding(.horizontal, 14).background(Theme.card, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline))
            if let e = error { Label(e, systemImage: "exclamationmark.triangle.fill").font(.system(size: 12.5)).foregroundStyle(Theme.danger) }
            if let k = restartHint { Label("Restart \(k.name) to load the new tools.", systemImage: "arrow.clockwise").font(.system(size: 12.5)).foregroundStyle(Theme.accent) }
            DisclosureGroup("Set up another agent manually", isExpanded: $manual) {
                VStack(alignment: .leading, spacing: 12) {
                    snippet("Claude Code", "claude mcp add cdesk --scope user -- \"\(server)\"")
                    snippet("Any MCP client (JSON)", "{\n  \"mcpServers\": {\n    \"cdesk\": { \"command\": \"\(server)\" }\n  }\n}")
                }.padding(.top, 8)
            }.font(.system(size: 12.5))
            Text("The server talks over stdio and uses the same colima and docker commands as the app. It works whether or not CDesk is open.").font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: 720)
        .onAppear { scan() }
    }

    private func row(_ st: AgentStatus) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon(st.kind)).font(.system(size: 15)).frame(width: 26).foregroundStyle(st.detected ? Theme.accent : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) { Text(st.kind.name).font(.system(size: 13, weight: .medium)); badge(st.state) }
                Text(detail(st)).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            if busy == st.kind { ProgressView().controlSize(.small) }
            else {
                switch st.state {
                case .notDetected: EmptyView()
                case .available: Button("Connect") { run(st.kind, install: true) }.buttonStyle(Pill(kind: .primary)).disabled(serverMissing || busy != nil)
                case .connected: Button("Disconnect") { run(st.kind, install: false) }.buttonStyle(Pill()).disabled(busy != nil)
                case .outdated:
                    HStack(spacing: 6) {
                        Button("Update") { run(st.kind, install: true) }.buttonStyle(Pill(kind: .primary)).disabled(serverMissing || busy != nil)
                        Button("Disconnect") { run(st.kind, install: false) }.buttonStyle(Pill()).disabled(busy != nil)
                    }
                }
            }
        }.padding(.vertical, 11)
    }

    @ViewBuilder private func badge(_ s: AgentStatus.State) -> some View {
        switch s {
        case .notDetected: Badge(text: "Not found")
        case .available: Badge(text: "Found", kind: .accent)
        case .connected: Badge(text: "Connected", kind: .ok)
        case .outdated: Badge(text: "Needs update", kind: .warn)
        }
    }

    private func detail(_ st: AgentStatus) -> String {
        switch st.state {
        case .notDetected: return "Not found on this Mac."
        case .available: return "Found. Not connected to cdesk yet."
        case .connected: return st.kind.needsRestart ? "Connected. Restart the app after changes." : "Connected. cdesk tools are available."
        case .outdated(let old): return "Points to \(old). Update it to use this copy of CDesk."
        }
    }

    private func icon(_ k: AgentKind) -> String {
        switch k {
        case .claudeCode, .geminiCLI, .codexCLI: "terminal"
        case .claudeDesktop: "bubble.left.and.text.bubble.right"
        case .cursor, .windsurf: "chevron.left.forwardslash.chevron.right"
        }
    }

    private func scan() { statuses = AgentIntegrations.scan(serverPath: server) }

    private func run(_ kind: AgentKind, install: Bool) {
        busy = kind; error = nil; restartHint = nil
        Task {
            do {
                if install { try await AgentIntegrations.install(kind, serverPath: server) } else { try await AgentIntegrations.remove(kind) }
                if install && kind.needsRestart { restartHint = kind }
                AppModel.shared.show(install ? "Connected \(kind.name)" : "Disconnected \(kind.name)")
            } catch { self.error = "\(kind.name): \(error.localizedDescription)" }
            scan(); busy = nil
        }
    }

    private func snippet(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { SectionLabel(title); Spacer(); CopyButton(text: text, label: "Copy") }
            Text(text).font(.system(size: 12, design: .monospaced)).foregroundStyle(Color(white: 0.88)).frame(maxWidth: .infinity, alignment: .leading).padding(12).background(Theme.terminal, in: RoundedRectangle(cornerRadius: 10)).textSelection(.enabled)
        }
    }
}

// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 kalahroudi

import SwiftUI
import ColimaKit

/// First-run guide. Detects Homebrew, Colima, the Docker CLI and a first profile, and sets up whatever is missing.
struct SetupView: View {
    let model = AppModel.shared
    var compact = false

    private var state: SetupState { model.setupState }
    private var rec: ColimaConfig { .recommended(for: model.hardware) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Let's get Colima running").font(.system(size: compact ? 15 : 18, weight: .semibold))
                Text("CDesk found what is missing and can set it all up for you.").font(.system(size: 12.5)).foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                step("Homebrew", ok: state.homebrew, detail: state.homebrew ? "Installed" : "Needed to install Colima and Docker")
                Divider()
                step("Colima", ok: state.colima, detail: state.colima ? "Installed" : "Runs the Linux VM for your containers")
                Divider()
                step("Docker CLI", ok: state.docker, detail: state.docker ? "Installed" : "The docker command")
                Divider()
                step("First profile", ok: !model.profiles.isEmpty, detail: model.profiles.isEmpty ? "\(rec.cpus) CPU · \(Int(rec.memoryGiB)) GB RAM · \(rec.diskGiB) GB disk · \(rec.vmType.rawValue) · \(rec.mountType.rawValue)" : "\(model.profiles.count) found")
            }.padding(.horizontal, 12).background(Theme.card, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline))

            if !state.homebrew && !state.toolsReady {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Install Homebrew first").font(.system(size: 13, weight: .semibold))
                    Text("Homebrew asks for your password, so it runs in Terminal where you can see it. Come back here when it is done.").font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Install Homebrew in Terminal") { TerminalLauncher.run(SetupState.homebrewInstallCommand, keepOpen: true) }.buttonStyle(Pill(kind: .primary))
                        Button("I installed it, check again") { Task { await model.refresh() } }.buttonStyle(Pill())
                    }
                    Link("About Homebrew (brew.sh)", destination: URL(string: "https://brew.sh")!).font(.system(size: 11.5))
                }.card()
            } else {
                HStack(spacing: 10) {
                    Button { model.setUpEverything() } label: {
                        HStack(spacing: 6) { if model.busy { ProgressView().controlSize(.small) }; Text(model.busy ? "Setting up…" : buttonTitle) }
                    }.buttonStyle(Pill(kind: .primary)).disabled(model.busy)
                    if model.busy, let t = model.runningTask { Text(t.lines.last ?? "").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1) }
                }
                if !state.toolsReady {
                    HStack(spacing: 6) {
                        Text("Or run it yourself:").font(.system(size: 11.5)).foregroundStyle(.secondary)
                        Text(state.manualCommand).font(.system(size: 11.5, design: .monospaced))
                        CopyButton(text: state.manualCommand, label: "Copy command")
                    }
                }
            }
        }.frame(maxWidth: 520, alignment: .leading)
    }

    private var buttonTitle: String {
        if !state.toolsReady && model.profiles.isEmpty { return "Install and create my first profile" }
        if !state.toolsReady { return "Install \(state.missingPackages.joined(separator: " and "))" }
        return "Create my first profile"
    }

    private func step(_ title: String, ok: Bool, detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle").foregroundStyle(ok ? Theme.ok : .secondary).font(.system(size: 15))
            VStack(alignment: .leading, spacing: 1) { Text(title).font(.system(size: 13, weight: .medium)); Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary) }
            Spacer()
        }.padding(.vertical, 9)
    }
}

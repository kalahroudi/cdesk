// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 kalahroudi

import SwiftUI

struct GlossaryEntry: Identifiable {
    let term: String, what: String, why: String
    var id: String { term }
}

enum Glossary {
    static let all: [GlossaryEntry] = [
        .init(term: "Colima", what: "A command line tool that runs Docker on a Mac by starting a small Linux virtual machine (VM) and putting the Docker engine inside it.", why: "Docker containers need Linux. Colima is a light, free alternative to Docker Desktop."),
        .init(term: "Profile", what: "One Colima VM with its own CPU, memory, disk and settings. The default profile is called default. Others are colima-<name> in Docker.", why: "Keep a lean profile for everyday work and a heavy one for big builds, and switch in one click."),
        .init(term: "VM type (vz / qemu)", what: "vz uses Apple's own Virtualization framework. qemu is a general-purpose emulator.", why: "On Apple silicon vz starts faster, uses less energy and enables virtiofs and Rosetta."),
        .init(term: "Mount type (virtiofs / sshfs / 9p)", what: "How folders on your Mac are shared into the VM and into containers.", why: "virtiofs is the fastest. sshfs and 9p are slower, which you notice in npm install and builds."),
        .init(term: "Rosetta", what: "Apple's translation layer that runs Intel (amd64) programs on Apple silicon.", why: "Much faster than emulating Intel images. Only needed if you use linux/amd64 images."),
        .init(term: "inotify (file-change events)", what: "A Linux feature that tells programs when files change.", why: "With it on, dev tools like nodemon and Vite notice edits you make on your Mac without constantly polling."),
        .init(term: "DNS resolvers", what: "The servers that turn names like github.com into addresses.", why: "By default the VM copies your Mac's DNS, which can break after a Wi-Fi switch or VPN. Fixed resolvers avoid that."),
        .init(term: "Restart vs recreate", what: "Restart stops and starts the same VM. Recreate deletes the VM and builds a new one.", why: "VM type, mount type, architecture and runtime are fixed when the VM is created, so changing them needs a recreate. That deletes containers, images and volumes inside it, so cdesk asks you to type the profile name and offers a backup."),
        .init(term: "Disk size", what: "The size of the VM's disk.", why: "It can only be made bigger, never smaller. Start with about 100 GB so image caching has room."),
        .init(term: "Docker context", what: "A setting that tells the docker command which engine to talk to.", why: "Colima creates colima (default profile) or colima-<name>. cdesk can switch it for you when you start a profile."),
        .init(term: "Container", what: "A running (or stopped) instance of an image: your app and everything it needs, isolated from the rest.", why: "Stopping a container keeps it; removing it deletes its writable layer."),
        .init(term: "Stack", what: "A group of containers started together from one docker compose file, for example web, database and cache.", why: "Managing them as one unit is easier: start, stop or restart the whole project at once."),
        .init(term: "Image", what: "The read-only template a container starts from.", why: "Images can be pulled again, so removing unused ones is safe. They take most of the disk."),
        .init(term: "Dangling image", what: "An untagged image layer left behind when a tag moves to a newer build.", why: "Nothing refers to it, so it is safe to remove."),
        .init(term: "Volume", what: "Storage that outlives containers, typically a database's data.", why: "Removing a volume deletes its data for good, so cdesk makes you type its name first."),
        .init(term: "Build cache", what: "Saved steps of previous image builds.", why: "Clearing it frees space; the next build is slower once, then fast again."),
        .init(term: "Prune", what: "Remove everything of one kind that nothing is using.", why: "A quick way to reclaim disk. cdesk shows what is reclaimable before you run it."),
        .init(term: "MCP", what: "Model Context Protocol, a standard way for AI agents to use tools.", why: "cdesk-mcp lets an agent manage Colima the same way you do here."),
    ]
}

struct GlossaryList: View {
    var only: [String]?
    @State private var query = ""
    var body: some View {
        let entries = Glossary.all.filter { e in
            (only == nil || only!.contains { e.term.localizedCaseInsensitiveContains($0) }) &&
            (query.isEmpty || e.term.localizedCaseInsensitiveContains(query) || e.what.localizedCaseInsensitiveContains(query))
        }
        VStack(alignment: .leading, spacing: 12) {
            if only == nil { SearchBox(prompt: "Search the glossary", text: $query).frame(maxWidth: 340) }
            ForEach(entries) { e in
                VStack(alignment: .leading, spacing: 6) {
                    Text(e.term).font(.system(size: 14, weight: .semibold))
                    Text(e.what).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .top, spacing: 6) { Text("Why").font(.system(size: 10.5, weight: .bold)).foregroundStyle(Theme.accent).padding(.top, 2); Text(e.why).font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                }.frame(maxWidth: 680, alignment: .leading).card(padding: 14)
            }
        }
    }
}

struct HelpPane: View {
    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: "Help & glossary", subtitle: "What things are, and why they are done this way.")
            ScrollView { GlossaryList().padding(22).frame(maxWidth: .infinity, alignment: .leading) }
        }
    }
}

// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 kalahroudi

import Foundation

public struct Hardware: Equatable, Sendable {
    public var memoryGiB: Double
    public var totalCores: Int
    public var performanceCores: Int
    public var isAppleSilicon: Bool

    public init(memoryGiB: Double, totalCores: Int, performanceCores: Int, isAppleSilicon: Bool) {
        self.memoryGiB = memoryGiB; self.totalCores = totalCores; self.performanceCores = performanceCores; self.isAppleSilicon = isAppleSilicon
    }

    public static func current() -> Hardware {
        func sysctlInt(_ name: String) -> Int? {
            var v: Int64 = 0; var size = MemoryLayout<Int64>.size
            return sysctlbyname(name, &v, &size, nil, 0) == 0 ? Int(v) : nil
        }
        let total = ProcessInfo.processInfo.processorCount
        #if arch(arm64)
        let apple = true
        #else
        let apple = false
        #endif
        return Hardware(memoryGiB: Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824,
                        totalCores: total, performanceCores: sysctlInt("hw.perflevel0.physicalcpu") ?? total, isAppleSilicon: apple)
    }
}

public struct Recommendation: Equatable, Sendable {
    public var cpus: Int
    public var memoryGiB: Double
    public var diskGiB: Int

    /// A starting point, not a rule: give Colima about half your cores and RAM,
    /// and leave the rest to macOS. 100 GiB of disk leaves room for the image cache (disk can only grow later).
    public static func forHardware(_ hw: Hardware) -> Recommendation {
        let cpus = max(2, hw.totalCores / 2)
        let mem = max(2, (hw.memoryGiB / 2).rounded(.down))
        return Recommendation(cpus: cpus, memoryGiB: mem, diskGiB: 100)
    }
}

public struct Advice: Identifiable, Equatable, Sendable {
    public enum Severity: Sendable { case good, suggestion, warning }
    public enum Effect: Sendable { case none, restart, recreate }
    public let id: String
    public let severity: Severity
    public let title: String
    public let detail: String
    public let effect: Effect
}

public enum Optimizer {
    /// Turns the current config plus what is observed on the machine into plain-language advice.
    public static func advice(config c: ColimaConfig, hardware hw: Hardware, usedMemoryGiB: Double? = nil, hasAmd64Images: Bool = false) -> [Advice] {
        var out: [Advice] = []
        if hw.isAppleSilicon {
            if c.vmType == .vz {
                out.append(Advice(id: "vz", severity: .good, title: "Using Apple's Virtualization framework", detail: "vz starts faster and uses less energy than QEMU on Apple silicon.", effect: .none))
            } else {
                out.append(Advice(id: "vz", severity: .suggestion, title: "Switch the VM type to vz", detail: "QEMU is a software emulator. vz uses Apple's native framework and unlocks virtiofs and Rosetta. It needs a delete and recreate.", effect: .recreate))
            }
        }
        if c.mountType == .virtiofs {
            out.append(Advice(id: "mount", severity: .good, title: "virtiofs mounts", detail: "Usually the fastest file sharing option, noticeable with npm install and builds.", effect: .none))
        } else if c.vmType == .vz {
            out.append(Advice(id: "mount", severity: .suggestion, title: "Switch mounts to virtiofs", detail: "\(c.mountType.rawValue) is slower for file-heavy work. virtiofs works with vz. It needs a delete and recreate.", effect: .recreate))
        }
        if c.dns.isEmpty {
            out.append(Advice(id: "dns", severity: .suggestion, title: "Set fixed DNS resolvers", detail: "Inherited DNS can break after switching Wi-Fi or connecting a VPN. 1.1.1.1 and 8.8.8.8 keep containers online.", effect: .restart))
        }
        if !c.mountInotify {
            out.append(Advice(id: "inotify", severity: .suggestion, title: "Turn on file-change events", detail: "Lets nodemon, Vite and webpack see edits made on your Mac without polling. Marked experimental by Colima.", effect: .restart))
        }
        if hasAmd64Images && !c.rosetta && c.vmType == .vz {
            out.append(Advice(id: "rosetta", severity: .suggestion, title: "Enable Rosetta for amd64 images", detail: "You have linux/amd64 images. Rosetta runs them much faster than QEMU emulation.", effect: .restart))
        }
        if c.kubernetes {
            out.append(Advice(id: "k8s", severity: .suggestion, title: "Kubernetes is on", detail: "Turn it off unless you use it. It adds a constant memory and CPU cost.", effect: .restart))
        }
        let rec = Recommendation.forHardware(hw)
        if c.memoryGiB > hw.memoryGiB * 0.6 {
            out.append(Advice(id: "mem-high", severity: .warning, title: "Memory is more than 60% of your Mac", detail: "macOS may start swapping. Recommended: \(Int(rec.memoryGiB)) GB.", effect: .restart))
        } else if let used = usedMemoryGiB, c.memoryGiB >= 4, used < c.memoryGiB * 0.25 {
            out.append(Advice(id: "mem-low-use", severity: .suggestion, title: "Memory is barely used", detail: String(format: "Using %.1f of %.0f GB. You could lower it and leave more for macOS.", used, c.memoryGiB), effect: .restart))
        }
        if c.cpus > max(2, hw.totalCores * 3 / 4) {
            out.append(Advice(id: "cpu-high", severity: .warning, title: "CPUs is above 75% of your cores", detail: "Recommended: \(rec.cpus). Leave cores for your editor and browser.", effect: .restart))
        }
        return out
    }
}

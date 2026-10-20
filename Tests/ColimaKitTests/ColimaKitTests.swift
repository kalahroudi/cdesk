// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 kalahroudi

import XCTest
@testable import ColimaKit

final class ColimaKitTests: XCTestCase {
    func testParseProfiles() {
        let json = #"{"name":"default","status":"Running","arch":"aarch64","cpus":4,"memory":8589934592,"disk":107374182400,"runtime":"docker"}"#
            + "\n" + #"{"name":"heavy","status":"Stopped","arch":"aarch64","cpus":6,"memory":12884901888,"disk":107374182400,"runtime":"docker","address":""}"#
        let p = Colima.parseProfiles(json)
        XCTAssertEqual(p.count, 2)
        XCTAssertTrue(p[0].isRunning)
        XCTAssertEqual(p[0].memoryGiB, 8)
        XCTAssertEqual(p[0].dockerContext, "colima")
        XCTAssertEqual(p[1].dockerContext, "colima-heavy")
        XCTAssertNil(p[1].address)
    }

    func testParseYAML() {
        let yaml = """
        cpu: 4
        disk: 100
        memory: 8
        arch: aarch64
        runtime: docker
        kubernetes:
          enabled: true
          version: v1.35.0+k3s1
        network:
          address: true
          dns:
            - 8.8.8.8
            - 8.8.4.4   # google
          hostAddresses: false
        vmType: vz
        rosetta: true
        mountType: virtiofs
        mountInotify: true
        """
        let c = ColimaConfig.parse(yaml: yaml)
        XCTAssertEqual(c.cpus, 4)
        XCTAssertEqual(c.memoryGiB, 8)
        XCTAssertEqual(c.dns, ["8.8.8.8", "8.8.4.4"])
        XCTAssertTrue(c.kubernetes)
        XCTAssertTrue(c.networkAddress)
        XCTAssertTrue(c.rosetta)
        XCTAssertTrue(c.mountInotify)
        XCTAssertEqual(c.vmType, .vz)
    }

    func testParseYAMLNullDNS() {
        let c = ColimaConfig.parse(yaml: "network:\n  dns: null\n  address: false\n")
        XCTAssertEqual(c.dns, [])
    }

    func testStartArguments() {
        var c = ColimaConfig()
        c.cpus = 4; c.memoryGiB = 8; c.diskGiB = 100; c.mountInotify = true; c.dns = ["1.1.1.1"]; c.rosetta = true
        let a = c.startArguments()
        XCTAssertEqual(Array(a.prefix(6)), ["--cpus", "4", "--memory", "8", "--disk", "100"])
        XCTAssertTrue(a.contains("--vz-rosetta"))
        XCTAssertTrue(a.contains("--mount-inotify"))
        XCTAssertEqual(c.commandLine(profile: "heavy").hasPrefix("colima start heavy --cpus 4"), true)
    }

    func testRosettaDroppedWithoutVZ() {
        var c = ColimaConfig(); c.vmType = .qemu; c.mountType = .sshfs; c.rosetta = true
        XCTAssertFalse(c.startArguments().contains("--vz-rosetta"))
    }

    func testRecreateReasons() {
        var old = ColimaConfig(); old.mountType = .sshfs
        var new = old; new.mountType = .virtiofs; new.memoryGiB = 8
        XCTAssertEqual(new.recreateReasons(comparedTo: old), [.mountType])
        XCTAssertTrue(new.differsRestartably(from: old))
        XCTAssertEqual(old.recreateReasons(comparedTo: old), [])
    }

    func testRecommendation() {
        let m1 = Hardware(memoryGiB: 16, totalCores: 8, performanceCores: 4, isAppleSilicon: true)
        XCTAssertEqual(Recommendation.forHardware(m1), Recommendation(cpus: 4, memoryGiB: 8, diskGiB: 100))
        let small = Hardware(memoryGiB: 8, totalCores: 8, performanceCores: 4, isAppleSilicon: true)
        XCTAssertEqual(Recommendation.forHardware(small).memoryGiB, 4)
    }

    func testAdviceSuggestsRecreateForSSHFS() {
        var c = ColimaConfig(); c.mountType = .sshfs
        let hw = Hardware(memoryGiB: 16, totalCores: 8, performanceCores: 4, isAppleSilicon: true)
        let a = Optimizer.advice(config: c, hardware: hw)
        XCTAssertEqual(a.first { $0.id == "mount" }?.effect, .recreate)
        XCTAssertNotNil(a.first { $0.id == "dns" })
    }

    func testAdviceWarnsOnHighMemory() {
        var c = ColimaConfig(); c.memoryGiB = 12
        let hw = Hardware(memoryGiB: 16, totalCores: 8, performanceCores: 4, isAppleSilicon: true)
        XCTAssertEqual(Optimizer.advice(config: c, hardware: hw).first { $0.id == "mem-high" }?.severity, .warning)
    }

    func testParseContainersAndStacks() {
        let json = #"{"ID":"ead38b479abd","Image":"postgres:16","Names":"db","State":"running","Status":"Up 4 days","Ports":"0.0.0.0:5432->5432/tcp, :::5432->5432/tcp","RunningFor":"4 days ago","Labels":"com.docker.compose.project=shop,com.docker.compose.service=db"}"#
            + "\n" + #"{"ID":"c9b7b9d22284","Image":"x","Names":"solo","State":"exited","Status":"Exited (1) 5 days ago","Ports":"","RunningFor":"5 days ago","Labels":""}"#
        let list = Docker.parseContainers(json)
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list[0].ports, "5432→5432")
        XCTAssertEqual(list[0].project, "shop")
        let stacks = Docker.stacks(from: list)
        XCTAssertEqual(stacks.count, 1)
        XCTAssertEqual(stacks[0].runningCount, 1)
    }

    func testParseLabelsWithCommaInValue() {
        let l = Docker.parseLabels("a=1,b=x,y,c=3")
        XCTAssertEqual(l["b"], "x,y")
        XCTAssertEqual(l["c"], "3")
    }

    func testParseStats() {
        let s = Docker.parseStats(#"{"ID":"ead38b479abd","CPUPerc":"1.50%","MemUsage":"26.3MiB / 7.737GiB"}"#)
        XCTAssertEqual(s.first?.cpuPercent, 1.5)
        XCTAssertEqual(s.first?.memoryBytes, Int64(26.3 * 1_048_576))
    }

    func testParseVerboseDf() {
        let json = #"{"Images":[{"Containers":"1","CreatedSince":"5 days ago","ID":"sha256:0ec50707bd713007","Repository":"<none>","Size":"2.34GB","Tag":"<none>"}],"Volumes":[{"Name":"pgdata","Driver":"local","Size":"343MB","Links":"1"},{"Name":"old","Driver":"local","Size":"0B","Links":"0"}]}"#
        let (images, volumes) = Docker.parseVerboseDf(json)
        XCTAssertEqual(images[0].id, "0ec50707bd71")
        XCTAssertTrue(images[0].isDangling)
        XCTAssertEqual(volumes.first?.name, "pgdata")
        XCTAssertFalse(volumes[1].isUsed)
    }

    func testParseUsageAndSizes() {
        let u = Docker.parseUsage(#"{"Active":"3","Reclaimable":"11.62GB (54%)","Size":"21.17GB","TotalCount":"13","Type":"Images"}"#)
        XCTAssertEqual(u.first?.reclaimableBytes, 11_620_000_000)
        XCTAssertEqual(parseSize("24.6kB"), 24_600)
        XCTAssertEqual(parseSize("0B"), 0)
    }

    // MARK: updates

    func testVersionOrdering() {
        XCTAssertTrue(Version.isNewer("v0.2.0", than: "0.1.9"))
        XCTAssertTrue(Version.isNewer("1.0", than: "0.9.9"))
        XCTAssertFalse(Version.isNewer("0.1.0", than: "0.1.0"))
        XCTAssertTrue(Version.isNewer("0.2.0", than: "0.2.0-rc.1"))
        XCTAssertFalse(Version.isNewer("0.2.0-rc.1", than: "0.2.0"))
        XCTAssertFalse(Version.isNewer("garbage", than: "0.1.0"))
    }

    func testParseRelease() {
        let json = #"{"tag_name":"v0.2.0","draft":false,"prerelease":false,"body":"- Faster start\n- Fix DNS","assets":[{"name":"CDesk-0.2.0.dmg","browser_download_url":"https://example.com/CDesk-0.2.0.dmg"},{"name":"SHA256SUMS","browser_download_url":"https://example.com/SHA256SUMS"}]}"#
        let r = UpdateChecker.parseRelease(Data(json.utf8))
        XCTAssertEqual(r?.version, "0.2.0")
        XCTAssertEqual(r?.dmgName, "CDesk-0.2.0.dmg")
        XCTAssertEqual(r?.notes, ["Faster start", "Fix DNS"])
        XCTAssertNotNil(r?.checksumsURL)
        XCTAssertNil(UpdateChecker.parseRelease(Data(#"{"tag_name":"v1","draft":true,"assets":[]}"#.utf8)))
        XCTAssertNil(UpdateChecker.parseRelease(Data(#"{"tag_name":"v1","assets":[]}"#.utf8)))
    }

    func testChecksumLookup() {
        let sums = "abc123  CDesk-0.2.0.dmg\nDEF456 *Other.dmg\n"
        XCTAssertEqual(UpdateChecker.checksum(in: sums, for: "CDesk-0.2.0.dmg"), "abc123")
        XCTAssertEqual(UpdateChecker.checksum(in: sums, for: "Other.dmg"), "def456")
        XCTAssertNil(UpdateChecker.checksum(in: sums, for: "missing.dmg"))
    }

    func testDecideCompare() throws {
        let ahead = #"{"status":"ahead","ahead_by":2,"commits":[{"commit":{"message":"First\n\nbody"}},{"commit":{"message":"Second"}}]}"#
        guard case .available(let info) = try UpdateChecker.decide(compareJSON: Data(ahead.utf8), head: "abcdef123456") else { return XCTFail() }
        XCTAssertEqual(info.aheadBy, 2); XCTAssertEqual(info.summaries, ["First", "Second"]); XCTAssertEqual(info.shortSha, "abcdef1")
        XCTAssertEqual(try UpdateChecker.decide(compareJSON: Data(#"{"status":"behind"}"#.utf8), head: "x"), .upToDate)
        guard case .notComparable = try UpdateChecker.decide(compareJSON: Data(#"{"status":"diverged"}"#.utf8), head: "x") else { return XCTFail() }
    }

    func testBuildInfoDirty() {
        let b = BuildInfo(commit: "0123456789abcdef-dirty")
        XCTAssertTrue(b.isDirty); XCTAssertEqual(b.cleanCommit, "0123456789abcdef"); XCTAssertEqual(b.shortCommit, "0123456")
        XCTAssertNil(BuildInfo(commit: "unknown").cleanCommit)
    }

    // MARK: setup

    func testSetupMissingPackages() {
        XCTAssertEqual(SetupState(homebrew: true, colima: false, docker: false).missingPackages, ["colima", "docker"])
        XCTAssertEqual(SetupState(homebrew: true, colima: true, docker: false).missingPackages, ["docker"])
        XCTAssertTrue(SetupState(homebrew: false, colima: true, docker: true).toolsReady)
        XCTAssertTrue(SetupState(homebrew: true, colima: false, docker: true).canAutoInstall)
        XCTAssertFalse(SetupState(homebrew: false, colima: false, docker: true).canAutoInstall)
        XCTAssertEqual(SetupState(homebrew: true, colima: false, docker: false).manualCommand, "brew install colima docker")
    }

    func testRecommendedConfig() {
        let m1 = Hardware(memoryGiB: 16, totalCores: 8, performanceCores: 4, isAppleSilicon: true)
        let c = ColimaConfig.recommended(for: m1)
        XCTAssertEqual(c.cpus, 4); XCTAssertEqual(c.memoryGiB, 8); XCTAssertEqual(c.arch, "aarch64")
        XCTAssertEqual(c.vmType, .vz); XCTAssertEqual(c.mountType, .virtiofs); XCTAssertTrue(c.mountInotify)
        let intel = Hardware(memoryGiB: 16, totalCores: 8, performanceCores: 8, isAppleSilicon: false)
        XCTAssertEqual(ColimaConfig.recommended(for: intel).arch, "x86_64")
    }

    // MARK: agents

    func testJSONInstallKeepsOtherSettings() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cdesk-agents-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.json")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try #"{"theme":"dark","mcpServers":{"other":{"command":"/bin/other"}}}"#.write(to: url, atomically: true, encoding: .utf8)

        try AgentIntegrations.jsonInstall(at: url, command: "/Applications/CDesk.app/Contents/MacOS/cdesk-mcp")
        XCTAssertEqual(AgentIntegrations.jsonCommand(at: url), "/Applications/CDesk.app/Contents/MacOS/cdesk-mcp")
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        XCTAssertEqual(root?["theme"] as? String, "dark")
        XCTAssertNotNil((root?["mcpServers"] as? [String: Any])?["other"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathExtension("cdesk-backup").path))

        try AgentIntegrations.jsonRemove(at: url)
        XCTAssertNil(AgentIntegrations.jsonCommand(at: url))
        let after = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        XCTAssertNotNil((after?["mcpServers"] as? [String: Any])?["other"])
    }

    func testJSONInstallCreatesMissingFileAndRefusesNonObject() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cdesk-agents-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("nested/mcp.json")
        try AgentIntegrations.jsonInstall(at: url, command: "/x/cdesk-mcp")
        XCTAssertEqual(AgentIntegrations.jsonCommand(at: url), "/x/cdesk-mcp")
        let bad = dir.appendingPathComponent("bad.json")
        try "[1,2]".write(to: bad, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try AgentIntegrations.jsonInstall(at: bad, command: "/x"))
        XCTAssertEqual(try String(contentsOf: bad, encoding: .utf8), "[1,2]")
    }

    func testCodexTomlDetection() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("codex-\(UUID().uuidString).toml")
        defer { try? FileManager.default.removeItem(at: url) }
        try "model = \"x\"\n\n[mcp_servers.other]\ncommand = \"/bin/other\"\n\n[mcp_servers.cdesk]\ncommand = \"/Applications/CDesk.app/Contents/MacOS/cdesk-mcp\"\nargs = []\n".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(AgentIntegrations.codexCommand(at: url), "/Applications/CDesk.app/Contents/MacOS/cdesk-mcp")
        XCTAssertNil(AgentIntegrations.codexCommand(at: url.appendingPathExtension("missing")))
    }

    func testServerPath() {
        XCTAssertEqual(AgentIntegrations.serverPath(bundlePath: "/Users/me/Apps/CDesk.app"), "/Users/me/Apps/CDesk.app/Contents/MacOS/cdesk-mcp")
        XCTAssertEqual(AgentIntegrations.serverPath(bundlePath: "/tmp/.build/debug"), "/Applications/CDesk.app/Contents/MacOS/cdesk-mcp")
    }
}

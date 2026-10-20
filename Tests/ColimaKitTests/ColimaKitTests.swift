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
}

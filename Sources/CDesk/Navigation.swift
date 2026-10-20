// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 kalahroudi

import SwiftUI

enum Section: String, CaseIterable, Identifiable {
    case overview, profiles, containers, images, cleanup, settings, help
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: "Overview"; case .profiles: "Profiles"; case .containers: "Containers"
        case .images: "Images & Volumes"; case .cleanup: "Cleanup"; case .settings: "Settings"; case .help: "Help & glossary"
        }
    }
    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"; case .profiles: "server.rack"; case .containers: "shippingbox"
        case .images: "square.stack.3d.up"; case .cleanup: "trash"; case .settings: "gearshape"; case .help: "questionmark.circle"
        }
    }
}

@MainActor @Observable
final class Nav {
    static let shared = Nav()
    var section: Section = .overview
}

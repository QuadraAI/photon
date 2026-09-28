//
//  AppTheme.swift
//  Photon
//

import Foundation

/// How Photon chooses its appearance.
///
/// This model deliberately stays free of SwiftUI so it can be persisted and
/// tested without a UI; ``AppTheme/colorScheme`` maps it to SwiftUI in an
/// extension.
nonisolated enum AppTheme: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Follow the system appearance, including automatic light/dark switching
    /// and the Control Center toggle.
    case system
    case light
    case dark

    var id: Self { self }
}

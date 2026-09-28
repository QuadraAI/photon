//
//  AppTheme+Presentation.swift
//  Photon
//

import SwiftUI

extension AppTheme {
    /// The scheme published to SwiftUI, or `nil` to follow the system.
    ///
    /// Passing `nil` rather than a concrete scheme is what keeps ``system``
    /// honouring the Control Center appearance toggle and scheduled light/dark
    /// switching.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// Name shown in the appearance menu.
    var menuTitle: LocalizedStringKey {
        switch self {
        case .system: "theme.system"
        case .light: "theme.light"
        case .dark: "theme.dark"
        }
    }

    /// Icon that pairs with ``menuTitle`` so the current choice is never
    /// conveyed by colour alone.
    var symbolName: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
}

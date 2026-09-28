//
//  AppLanguage.swift
//  Photon
//

import Foundation

/// A user-selectable interface language.
///
/// `system` follows the device language. The other cases pin Photon to one of
/// the localizations in `Localizable.xcstrings` and take effect immediately —
/// no relaunch required.
nonisolated enum AppLanguage: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Follow the device language.
    case system
    case english = "en"
    case french = "fr"

    var id: Self { self }

    /// The locale identifier published through the SwiftUI environment, or
    /// `nil` when the device locale should be used instead.
    var localeIdentifier: String? {
        switch self {
        case .system: nil
        case .english: "en"
        case .french: "fr"
        }
    }

    /// The locale that drives string lookup and formatting across the UI.
    ///
    /// `.autoupdatingCurrent` keeps ``system`` in step with System Settings
    /// while the app is running.
    var locale: Locale {
        guard let localeIdentifier else { return .autoupdatingCurrent }
        return Locale(identifier: localeIdentifier)
    }
}

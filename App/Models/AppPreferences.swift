//
//  AppPreferences.swift
//  Photon
//

import Foundation

/// Settings the user controls that survive across launches.
///
/// There is deliberately no "remember the last folder" flag: Photon always
/// remembers it and always reopens it. Asking the user to confirm a choice they
/// already made is worse than simply honouring it.
///
/// `nonisolated` because ``PreferencesStoring`` is read from background work as
/// well as the main actor.
nonisolated struct AppPreferences: Equatable, Sendable {
    /// Interface language. Defaults to the device language.
    var language: AppLanguage = .system

    /// Appearance. Defaults to the device appearance.
    var theme: AppTheme = .system
}

//
//  UserDefaultsPreferencesStore.swift
//  Photon
//

import Foundation

/// ``PreferencesStoring`` backed by `UserDefaults`.
///
/// Marked `@unchecked Sendable` because `UserDefaults` is documented as
/// thread-safe but the SDK does not annotate it as `Sendable`, and
/// `nonisolated` to opt out of the target's default main-actor isolation.
nonisolated struct UserDefaultsPreferencesStore: PreferencesStoring, @unchecked Sendable {
    /// Keys are namespaced so they cannot collide with unrelated defaults.
    private enum Key {
        static let language = "preferences.language"
        static let theme = "preferences.theme"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func load() -> AppPreferences {
        var preferences = AppPreferences()

        if let raw = defaults.string(forKey: Key.language),
           let language = AppLanguage(rawValue: raw) {
            preferences.language = language
        }

        if let raw = defaults.string(forKey: Key.theme),
           let theme = AppTheme(rawValue: raw) {
            preferences.theme = theme
        }

        return preferences
    }

    func save(_ preferences: AppPreferences) {
        defaults.set(preferences.language.rawValue, forKey: Key.language)
        defaults.set(preferences.theme.rawValue, forKey: Key.theme)
    }
}

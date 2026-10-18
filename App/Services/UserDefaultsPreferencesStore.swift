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
        static let exportFormat = "preferences.exportFormat"
        static let exportQuality = "preferences.exportQuality"
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

        if let raw = defaults.string(forKey: Key.exportFormat),
           let format = ExportFormat(rawValue: raw) {
            preferences.exportFormat = format
        }

        // A real `NSNumber` rather than `double(forKey:)`: a corrupt string
        // would otherwise read as zero and be accepted as a quality nobody chose.
        if let number = defaults.object(forKey: Key.exportQuality) as? NSNumber {
            preferences.exportQuality = number.doubleValue.clamped(to: ExportOptions.qualityRange)
        }

        return preferences
    }

    func save(_ preferences: AppPreferences) {
        defaults.set(preferences.language.rawValue, forKey: Key.language)
        defaults.set(preferences.theme.rawValue, forKey: Key.theme)
        defaults.set(preferences.exportFormat.rawValue, forKey: Key.exportFormat)
        defaults.set(preferences.exportQuality, forKey: Key.exportQuality)
    }
}

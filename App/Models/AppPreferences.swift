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

    /// The last format the export sheet used.
    ///
    /// Remembered rather than asked again on every export: a photographer who
    /// exports a shoot as JPEG once is likely to want JPEG for the next frame.
    var exportFormat: ExportFormat = .jpeg

    /// The last compression quality the export sheet used, in `0...1`.
    ///
    /// Meaningless for PNG and TIFF, which is why the sheet hides the slider
    /// for them, but kept so switching back to a lossy format restores it.
    var exportQuality: Double = ExportOptions.defaultQuality
}

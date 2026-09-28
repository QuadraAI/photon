//
//  PreferencesStoring.swift
//  Photon
//

import Foundation

/// Reads and writes ``AppPreferences``.
///
/// The store is `Sendable` so it can be handed to background work as well as
/// the main actor; conformances must be safe to call from any isolation
/// domain.
///
/// `nonisolated` is required because the target builds with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; without it every requirement
/// would be main-actor-bound and the store could never be used off the main
/// thread.
nonisolated protocol PreferencesStoring: Sendable {
    /// The persisted preferences, falling back to defaults for anything the
    /// user has never changed.
    func load() -> AppPreferences

    /// Persists `preferences`.
    func save(_ preferences: AppPreferences)
}

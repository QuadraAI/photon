//
//  InMemoryPreferencesStore.swift
//  PhotonTests
//

import Foundation
import Synchronization

@testable import Photon

/// In-memory ``PreferencesStoring`` that records how often it is written to.
final class InMemoryPreferencesStore: PreferencesStoring, Sendable {
    private let storage: Mutex<AppPreferences>
    private let writeCount = Mutex(0)

    /// Creates a store seeded with `initial`.
    init(initial: AppPreferences = AppPreferences()) {
        storage = Mutex(initial)
    }

    /// The value currently held.
    var stored: AppPreferences {
        storage.withLock { $0 }
    }

    /// How many times ``save(_:)`` has been called, so tests can prove the view
    /// model does not write when nothing changed.
    var saves: Int {
        writeCount.withLock { $0 }
    }

    func load() -> AppPreferences {
        storage.withLock { $0 }
    }

    func save(_ preferences: AppPreferences) {
        storage.withLock { $0 = preferences }
        writeCount.withLock { $0 += 1 }
    }
}

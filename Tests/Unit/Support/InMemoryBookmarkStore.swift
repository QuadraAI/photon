//
//  InMemoryBookmarkStore.swift
//  PhotonTests
//

import Foundation
import Synchronization

@testable import Photon

/// In-memory ``BookmarkStoring``.
final class InMemoryBookmarkStore: BookmarkStoring, Sendable {
    private let storage: Mutex<Data?>

    /// Creates a store seeded with `bookmark`.
    init(bookmark: Data? = nil) {
        storage = Mutex(bookmark)
    }

    /// The value currently held.
    var storedBookmark: Data? {
        storage.withLock { $0 }
    }

    func loadBookmark() -> Data? {
        storage.withLock { $0 }
    }

    func saveBookmark(_ bookmark: Data?) {
        storage.withLock { $0 = bookmark }
    }
}

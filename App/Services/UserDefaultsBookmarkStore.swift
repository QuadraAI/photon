//
//  UserDefaultsBookmarkStore.swift
//  Photon
//

import Foundation

/// ``BookmarkStoring`` backed by `UserDefaults`.
///
/// Bookmark blobs are a few hundred bytes, so `UserDefaults` is a good fit and
/// avoids standing up a database for a single value.
nonisolated struct UserDefaultsBookmarkStore: BookmarkStoring, @unchecked Sendable {
    private static let key = "folder.rememberedBookmark"

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func loadBookmark() -> Data? {
        defaults.data(forKey: Self.key)
    }

    func saveBookmark(_ bookmark: Data?) {
        guard let bookmark else {
            defaults.removeObject(forKey: Self.key)
            return
        }
        defaults.set(bookmark, forKey: Self.key)
    }
}

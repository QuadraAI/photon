//
//  BookmarkStoring.swift
//  Photon
//

import Foundation

/// Remembers the folder Photon should reopen on a later launch.
///
/// `nonisolated` for the same reason as ``PreferencesStoring``: the bookmark is
/// written from ``AppViewModel`` today and from background work tomorrow.
nonisolated protocol BookmarkStoring: Sendable {
    /// The stored bookmark, or `nil` when no folder has been remembered.
    func loadBookmark() -> Data?

    /// Persists `bookmark`, or clears the stored value when passed `nil`.
    func saveBookmark(_ bookmark: Data?)
}

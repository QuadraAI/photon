//
//  TestSupport.swift
//  PhotonTests
//

import Foundation

@testable import Photon

/// Builds an ``AppViewModel`` around in-memory services.
@MainActor
func makeAppViewModel(
    preferences: InMemoryPreferencesStore = InMemoryPreferencesStore(),
    bookmarks: InMemoryBookmarkStore = InMemoryBookmarkStore(),
    folderAccess: StubFolderAccess = StubFolderAccess(folder: .fixture())
) -> AppViewModel {
    AppViewModel(
        preferencesStore: preferences,
        bookmarkStore: bookmarks,
        folderAccess: folderAccess
    )
}

/// The URL ``AuthorizedFolder/fixture(name:bookmark:)`` reports, so tests can
/// compare a picked URL against the resulting folder without repeating it.
extension AuthorizedFolder {
    static var fixtureURL: URL {
        fixture().url
    }

    /// A folder named `name`, for tests that need two different ones.
    static func fixture(name: String) -> AuthorizedFolder {
        fixture(name: name, bookmark: Data([0xBE, 0xEF]))
    }
}

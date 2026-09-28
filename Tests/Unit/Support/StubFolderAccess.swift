//
//  StubFolderAccess.swift
//  PhotonTests
//

import Foundation

@testable import Photon

/// Scriptable ``FolderAccessing`` that never touches the file system.
actor StubFolderAccess: FolderAccessing {
    /// The folder handed back on success.
    let folder: AuthorizedFolder

    private var failure: FolderAccessError?

    /// URLs passed to ``authorize(_:)``, in call order.
    private(set) var requestedURLs: [URL] = []

    /// Bookmarks passed to ``restore(_:)``, in call order.
    private(set) var restoredBookmarks: [Data] = []

    init(folder: AuthorizedFolder, failure: FolderAccessError? = nil) {
        self.folder = folder
        self.failure = failure
    }

    /// Makes later calls fail with `error`, or clears the failure when `nil`.
    ///
    /// Lets a test open one folder successfully and then fail the next attempt,
    /// which is how a failed folder *switch* is exercised.
    func setFailure(_ error: FolderAccessError?) {
        failure = error
    }

    func authorize(_ url: URL) throws(FolderAccessError) -> AuthorizedFolder {
        requestedURLs.append(url)
        if let failure { throw failure }
        return AuthorizedFolder(url: url, bookmark: folder.bookmark)
    }

    func restore(_ bookmark: Data) throws(FolderAccessError) -> AuthorizedFolder {
        restoredBookmarks.append(bookmark)
        if let failure { throw failure }
        // Echo the bookmark back so tests can prove a refreshed one is stored.
        return AuthorizedFolder(url: folder.url, bookmark: bookmark)
    }
}

extension AuthorizedFolder {
    /// Fixture used across the view-model tests.
    ///
    /// Pass `bookmark: nil` to model a folder the system granted access to but
    /// would not mint a bookmark for.
    static func fixture(
        name: String = "Photos",
        bookmark: Data? = Data([0xBE, 0xEF])
    ) -> AuthorizedFolder {
        AuthorizedFolder(
            url: URL(filePath: "/tmp/\(name)", directoryHint: .isDirectory),
            bookmark: bookmark
        )
    }
}

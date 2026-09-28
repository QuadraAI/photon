//
//  SecurityScopedFolderAccessTests.swift
//  PhotonTests
//

import Foundation
import Testing

@testable import Photon

/// These exercise the real bookmark APIs against a throwaway directory, which
/// is the part a stub cannot prove: that the bookmark we hand to
/// ``BookmarkStoring`` can actually be resolved in a later launch.
@Suite("Security-scoped folder access")
struct SecurityScopedFolderAccessTests {
    @Test("A folder is authorized and can be reopened from its bookmark")
    func roundTrip() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }

        let access = SecurityScopedFolderAccess()
        let authorized = try await access.authorize(folder.url)

        #expect(authorized.url.path(percentEncoded: false) == folder.url.path(percentEncoded: false))
        let bookmark = try #require(authorized.bookmark, "A folder inside the container still gets a bookmark")
        #expect(bookmark.isEmpty == false)

        let restored = try await access.restore(bookmark)

        #expect(restored.url.path(percentEncoded: false) == folder.url.path(percentEncoded: false))
    }

    @Test("Authorizing a second folder does not disturb the first bookmark")
    func authorizingTwiceKeepsBothUsable() async throws {
        let first = try TemporaryFolder()
        let second = try TemporaryFolder()
        defer {
            first.remove()
            second.remove()
        }

        let access = SecurityScopedFolderAccess()
        let firstGrant = try await access.authorize(first.url)
        let secondGrant = try await access.authorize(second.url)

        let restored = try await access.restore(#require(firstGrant.bookmark))

        #expect(restored.url.path(percentEncoded: false) == first.url.path(percentEncoded: false))
        #expect(secondGrant.url.path(percentEncoded: false) == second.url.path(percentEncoded: false))
    }

    @Test("A file is rejected because it is not a folder")
    func rejectsFile() async throws {
        let folder = try TemporaryFolder()
        defer { folder.remove() }
        let file = folder.url.appending(path: "photo.jpg")
        try Data([0xFF, 0xD8, 0xFF]).write(to: file)

        let access = SecurityScopedFolderAccess()

        await #expect(throws: FolderAccessError.notADirectory) {
            try await access.authorize(file)
        }
    }

    @Test("A path that does not exist is rejected")
    func rejectsMissingPath() async {
        let access = SecurityScopedFolderAccess()

        await #expect(throws: FolderAccessError.notADirectory) {
            try await access.authorize(URL(filePath: "/nowhere/\(UUID().uuidString)"))
        }
    }

    @Test("Bookmark data that is not a bookmark cannot be resolved")
    func rejectsCorruptBookmark() async {
        let access = SecurityScopedFolderAccess()

        await #expect(throws: FolderAccessError.bookmarkResolutionFailed) {
            try await access.restore(Data([0x00, 0x01, 0x02, 0x03]))
        }
    }
}

/// A unique temporary directory that cleans up after itself.
private struct TemporaryFolder {
    let url: URL

    init() throws {
        url = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

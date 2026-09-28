//
//  SecurityScopedFolderAccess.swift
//  Photon
//

import Foundation
import os

/// ``FolderAccessing`` backed by security-scoped bookmarks.
///
/// A bookmark is the only way a sandboxed app can reopen a folder the user
/// picked in an earlier launch. The two platforms differ in how the security
/// scope is attached; see ``URL/BookmarkCreationOptions/photonPersistent``.
actor SecurityScopedFolderAccess: FolderAccessing {
    private let logger = Logger(subsystem: "com.quadra.Photon", category: "FolderAccess")

    func authorize(_ url: URL) throws(FolderAccessError) -> AuthorizedFolder {
        // `resourceValues` reads metadata the sandbox exposes without a scope,
        // so this check is safe to make first and gives the most useful error.
        guard isDirectory(url) else {
            throw .notADirectory
        }

        // The scope has to be engaged *before* the bookmark is minted. A URL
        // handed over by the open panel is only fully accessible inside its
        // scope, and `bookmarkData(options: .withSecurityScope)` needs that
        // access — creating the bookmark first fails on macOS.
        try startAccessing(url)

        return AuthorizedFolder(url: url, bookmark: makeBookmark(for: url))
    }

    func restore(_ bookmark: Data) throws(FolderAccessError) -> AuthorizedFolder {
        var isStale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: bookmark,
                options: .photonPersistent,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            logger.error("Bookmark resolution failed: \(error.localizedDescription)")
            throw .bookmarkResolutionFailed
        }

        try startAccessing(url)

        // A stale bookmark still resolved, but should be replaced before the
        // folder moves or its volume unmounts. If the refresh fails the old
        // bookmark is still better than none.
        guard isStale, let refreshed = makeBookmark(for: url) else {
            return AuthorizedFolder(url: url, bookmark: bookmark)
        }
        return AuthorizedFolder(url: url, bookmark: refreshed)
    }

    // MARK: - File system

    private func isDirectory(_ url: URL) -> Bool {
        do {
            return try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
        } catch {
            logger.error("Could not read resource values for \(url.path(percentEncoded: false))")
            return false
        }
    }

    /// Mints a bookmark for `url`, or returns `nil` if the system refuses.
    ///
    /// Deliberately non-throwing: failing to *remember* a folder must never stop
    /// the user working in it. The folder opens either way; the only cost is
    /// that it will not be reopened next launch.
    private func makeBookmark(for url: URL) -> Data? {
        do {
            return try url.bookmarkData(
                options: .photonPersistent,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            logger.error("Bookmark creation failed for \(url.path(percentEncoded: false)): \(error as NSError)")
            return nil
        }
    }

    /// Engages the security scope for `url`.
    ///
    /// The scope is deliberately never released. Photon holds every folder it
    /// has opened for the life of the process, because more than one window can
    /// be working in a different folder at once — releasing on replace would
    /// revoke the grant out from under the other window and its image loads
    /// would start failing.
    ///
    /// - Throws: ``FolderAccessError/accessDenied`` when the folder is
    ///   unreadable, releasing the scope it did open.
    private func startAccessing(_ url: URL) throws(FolderAccessError) {
        let isScoped = url.startAccessingSecurityScopedResource()

        // Without a scope the folder is only reachable if it already sits inside
        // the app's own container, so reject it only when genuinely unreadable.
        guard isScoped || FileManager.default.isReadableFile(atPath: url.path(percentEncoded: false)) else {
            logger.error("Access denied for \(url.path(percentEncoded: false))")
            if isScoped { url.stopAccessingSecurityScopedResource() }
            throw .accessDenied
        }
    }
}

//
//  URL+Bookmarks.swift
//  Photon
//

import Foundation

extension URL.BookmarkCreationOptions {
    /// Options that mint a bookmark a sandboxed app can reopen in a later
    /// launch.
    ///
    /// macOS requires `.withSecurityScope`. iPadOS marks that option
    /// unavailable — `NSURLBookmarkCreationWithSecurityScope` is
    /// `API_UNAVAILABLE(ios)` — and instead embeds an implicit security scope
    /// in bookmarks created without it, which is what
    /// `startAccessingSecurityScopedResource()` later activates.
    nonisolated static var photonPersistent: Self {
        #if os(macOS)
        return .withSecurityScope
        #else
        return []
        #endif
    }
}

extension URL.BookmarkResolutionOptions {
    /// Options that restore the access granted when the bookmark was created.
    ///
    /// `.withoutUI` keeps a moved or offline folder from raising a system
    /// dialog behind our own error handling.
    nonisolated static var photonPersistent: Self {
        #if os(macOS)
        return [.withSecurityScope, .withoutUI]
        #else
        return [.withoutUI]
        #endif
    }
}

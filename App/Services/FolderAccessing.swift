//
//  FolderAccessing.swift
//  Photon
//

import Foundation

/// Grants Photon durable access to folders the user picks.
///
/// An actor because bookmark creation and resolution both touch the file system,
/// and because the active grant is mutable state.
///
/// Both methods are typed `throws(FolderAccessError)`: callers have exactly one
/// error to handle, and no unreachable fallback branch to write.
protocol FolderAccessing: Actor {
    /// Starts accessing `url` and tries to mint a bookmark for it.
    ///
    /// Persisting the returned bookmark is the caller's job — this type only
    /// talks to the file system. The folder counts as open even when
    /// ``AuthorizedFolder/bookmark`` comes back `nil`.
    ///
    /// - Throws: ``FolderAccessError`` when `url` is not a folder, or the system
    ///   refuses access to it.
    func authorize(_ url: URL) throws(FolderAccessError) -> AuthorizedFolder

    /// Restores access from a bookmark produced by ``authorize(_:)``.
    ///
    /// - Throws: ``FolderAccessError/bookmarkResolutionFailed`` when the
    ///   bookmark no longer points anywhere reachable.
    func restore(_ bookmark: Data) throws(FolderAccessError) -> AuthorizedFolder
}

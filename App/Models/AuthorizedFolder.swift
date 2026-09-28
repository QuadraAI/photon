//
//  AuthorizedFolder.swift
//  Photon
//

import Foundation

/// A folder the user granted Photon access to.
///
/// `nonisolated` because the value crosses into ``FolderAccessing``, which is
/// an actor. The target builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`,
/// so pure data types have to opt out explicitly.
nonisolated struct AuthorizedFolder: Equatable, Sendable {
    /// Location of the folder on disk.
    let url: URL

    /// Bookmark data that can be persisted and resolved in a later launch, or
    /// `nil` when the system would not mint one.
    ///
    /// A missing bookmark is not a failure to *open* the folder — the folder is
    /// granted either way. It only means the grant cannot outlive the process,
    /// which matters solely when the user asked Photon to reopen the folder
    /// next time.
    let bookmark: Data?
}

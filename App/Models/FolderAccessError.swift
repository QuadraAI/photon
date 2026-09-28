//
//  FolderAccessError.swift
//  Photon
//

import Foundation

/// Why Photon could not open the folder the user picked.
///
/// Notably absent is "could not remember the folder": failing to mint a
/// bookmark no longer fails the open. The folder works either way — the only
/// consequence is that it will not be reopened next launch, which is not worth
/// an alert the user cannot act on.
nonisolated enum FolderAccessError: Error, Equatable, Sendable {
    /// The selected URL points at a file, not a folder.
    case notADirectory

    /// The system refused access to the folder.
    case accessDenied

    /// A stored bookmark could not be resolved, typically because the folder
    /// was moved or lives on a volume that is no longer mounted.
    case bookmarkResolutionFailed
}

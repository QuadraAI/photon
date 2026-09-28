//
//  PhotoLibraryError.swift
//  Photon
//

import Foundation

/// Why Photon could not list a folder's photos.
///
/// Deliberately narrow: a subfolder that cannot be read is skipped rather than
/// failing the whole scan, so this only means the folder itself is unusable.
nonisolated enum PhotoLibraryError: Error, Equatable, Sendable {
    /// The folder could not be enumerated at all.
    case unreadable
}

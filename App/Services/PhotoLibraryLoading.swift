//
//  PhotoLibraryLoading.swift
//  Photon
//

import Foundation

/// Finds the photos under a folder.
///
/// Typed `throws(PhotoLibraryError)` so callers have exactly one error to
/// handle, matching ``FolderAccessing``.
protocol PhotoLibraryLoading: Sendable {
    /// Every image in `folder` and its subfolders, sorted by file name.
    ///
    /// - Throws: ``PhotoLibraryError/unreadable`` when the folder itself cannot
    ///   be opened. Unreadable *sub*folders are skipped rather than failing the
    ///   whole scan.
    func photos(in folder: URL) async throws(PhotoLibraryError) -> [PhotoItem]
}

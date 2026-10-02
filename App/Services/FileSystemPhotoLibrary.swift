//
//  FileSystemPhotoLibrary.swift
//  Photon
//

import Foundation
import UniformTypeIdentifiers
import os

/// ``PhotoLibraryLoading`` backed by a recursive directory walk.
actor FileSystemPhotoLibrary: PhotoLibraryLoading {
    /// How often the walk checks for cancellation.
    nonisolated private static let cancellationCheckInterval = 256

    /// One logger, shared with the skip log the walk's error handler calls.
    nonisolated private static let logger = Logger(subsystem: "com.quadra.Photon", category: "PhotoLibrary")

    func photos(in folder: URL) async throws(PhotoLibraryError) -> [PhotoItem] {
        // The walk itself is synchronous on purpose: `DirectoryEnumerator` is
        // `NSFastEnumeration`-based and its iterator is marked `noasync`. This
        // actor runs off the main thread, so blocking it is the right trade.
        sorted(try scan(folder))
    }

    // MARK: - Internals

    private func scan(_ folder: URL) throws(PhotoLibraryError) -> [PhotoItem] {
        // `enumerator(at:)` happily returns an enumerator for a path that is not
        // there and simply yields nothing, so the folder is checked first —
        // otherwise a missing or forbidden folder would look like an empty one.
        let root = trimmedPath(folder)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root, isDirectory: &isDirectory),
              isDirectory.boolValue,
              FileManager.default.isReadableFile(atPath: root)
        else {
            throw .unreadable
        }

        let keys: [URLResourceKey] = [.isDirectoryKey, .contentTypeKey]
        guard
            let enumerator = FileManager.default.enumerator(
                at: folder,
                includingPropertiesForKeys: keys,
                // `.skipsPackageDescendants` keeps Photon out of bundles such as
                // `Photos Library.photoslibrary`, whose innards are not photos
                // the user can edit.
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { url, error in
                    // A subfolder we cannot read is not a reason to fail the
                    // whole scan; skip it and carry on.
                    Self.logSkipped(url, error: error)
                    return true
                }
            )
        else {
            throw .unreadable
        }

        var photos: [PhotoItem] = []
        var visited = 0

        for case let url as URL in enumerator {
            visited += 1
            if visited.isMultiple(of: Self.cancellationCheckInterval), Task.isCancelled { return [] }

            guard let type = photoType(url) else { continue }
            photos.append(
                PhotoItem(
                    url: url,
                    subfolderPath: relativeFolder(of: url, under: root),
                    isRAW: type.conforms(to: .rawImage)
                )
            )
        }

        return photos
    }

    /// The file's image type, or nil when it is a directory or not an image.
    private func photoType(_ url: URL) -> UTType? {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentTypeKey])
        guard values?.isDirectory != true else { return nil }

        return Self.imageType(reported: values?.contentType, for: url)
    }

    /// The image type a file is: what the system reported about it, and failing
    /// that what the system reports about its name.
    ///
    /// Both answers are the system's, from the same declaration table — so this is
    /// not the second list of extensions the approach exists to avoid. It is what
    /// keeps a file from vanishing out of the folder without a word: a resource
    /// lookup comes back empty on some volumes, and for a type the system has no
    /// mapping for, and the file is an image either way.
    ///
    /// `nonisolated` and static so it is the whole of the decision, with no
    /// filesystem under it to have to arrange in a test.
    nonisolated static func imageType(reported: UTType?, for url: URL) -> UTType? {
        guard let type = reported ?? UTType(filenameExtension: url.pathExtension),
              type.conforms(to: .image)
        else { return nil }

        return type
    }

    /// The photo's folder relative to the scanned root, empty for the root.
    ///
    /// `base` arrives already trimmed, so this does no path work of its own.
    private func relativeFolder(of url: URL, under base: String) -> String {
        let parent = trimmedPath(url.deletingLastPathComponent())
        guard parent != base else { return "" }

        return parent.hasPrefix(base)
            ? String(parent.dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            : parent
    }

    /// `URL.path(percentEncoded:)` keeps a directory's trailing slash, which
    /// would otherwise leak into the folder names and the path comparisons.
    private func trimmedPath(_ url: URL) -> String {
        var path = url.path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        return path
    }

    /// `localizedStandardCompare` so "IMG_2" sorts before "IMG_10", and the
    /// folder breaks ties so the order does not depend on the walk.
    private func sorted(_ photos: [PhotoItem]) -> [PhotoItem] {
        photos.sorted { lhs, rhs in
            let byName = lhs.name.localizedStandardCompare(rhs.name)
            if byName != .orderedSame { return byName == .orderedAscending }
            return lhs.subfolderPath.localizedStandardCompare(rhs.subfolderPath) == .orderedAscending
        }
    }

    private nonisolated static func logSkipped(_ url: URL, error: any Error) {
        logger.error("Skipping \(url.path(percentEncoded: false)): \(error.localizedDescription)")
    }
}

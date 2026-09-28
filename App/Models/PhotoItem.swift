//
//  PhotoItem.swift
//  Photon
//

import Foundation
import UniformTypeIdentifiers

/// One photo found under the window's folder.
nonisolated struct PhotoItem: Identifiable, Equatable, Sendable, Hashable {
    /// Absolute location of the file.
    let url: URL

    /// The containing folder relative to the scanned root, empty when the photo
    /// sits directly in the root.
    ///
    /// Carried because the sidebar shows file names only, and two subfolders can
    /// hold the same name — this is what tells them apart.
    let subfolderPath: String

    /// The file's uniform type, as the scanner found it.
    ///
    /// Stored rather than re-derived from the extension: the scan already reads
    /// it, and the sidebar draws a glyph from it on every row.
    let contentType: UTType?

    var id: URL { url }

    /// File name including its extension.
    var name: String { url.lastPathComponent }

    /// File name without its extension, so the sidebar can set the two apart.
    var baseName: String { url.deletingPathExtension().lastPathComponent }

    /// The extension including its leading dot, empty when the file has none.
    var fileExtension: String {
        url.pathExtension.isEmpty ? "" : "." + url.pathExtension
    }
}

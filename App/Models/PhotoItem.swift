//
//  PhotoItem.swift
//  Photon
//

import Foundation

/// One photo found under the window's folder.
nonisolated struct PhotoItem: Identifiable, Equatable, Sendable, Hashable {
    /// Absolute location of the file.
    let url: URL

    /// File name including its extension.
    ///
    /// Stored because the scanner's sort compares it tens of thousands of times.
    let name: String

    /// The containing folder relative to the scanned root, empty when the photo
    /// sits directly in the root.
    ///
    /// Carried because the sidebar shows file names only, and two subfolders can
    /// hold the same name — this is what tells them apart.
    let subfolderPath: String

    /// Whether the file needs the RAW pipeline.
    ///
    /// A `Bool` rather than the scanned `UTType`, which the sidebar only ever
    /// asked to conform to `.rawImage`.
    let isRAW: Bool

    var id: URL { url }

    /// File name without its extension, so the sidebar can set the two apart.
    var baseName: String { url.deletingPathExtension().lastPathComponent }

    /// The extension including its leading dot, empty when the file has none.
    var fileExtension: String {
        url.pathExtension.isEmpty ? "" : "." + url.pathExtension
    }

    /// Reads the file name once, so no reader has to.
    init(url: URL, subfolderPath: String, isRAW: Bool) {
        self.url = url
        self.name = url.lastPathComponent
        self.subfolderPath = subfolderPath
        self.isRAW = isRAW
    }
}

//
//  PhotoExporting.swift
//  Photon
//

import CoreGraphics
import Foundation

/// Turns a photo and a recipe into a file with a name, metadata and a place on
/// disk. Separate from ``PhotoEditing``, which only produces pixels.
nonisolated protocol PhotoExporting: Sendable {
    func export(_ request: PhotoExportRequest) async throws(PhotoExportError) -> ExportedPhoto
}

/// One export, decided.
nonisolated struct PhotoExportRequest: Sendable {
    let photo: PhotoItem

    /// The committed recipe, never the open tool's draft.
    let recipe: EditRecipe

    let folder: URL
    let baseName: String
    let options: ExportOptions
}

/// What was written.
nonisolated struct ExportedPhoto: Equatable, Sendable {
    /// The final URL, after collision handling.
    let url: URL

    let pixelSize: CGSize
    let byteCount: Int
}

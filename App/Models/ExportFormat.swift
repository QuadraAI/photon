//
//  ExportFormat.swift
//  Photon
//

import Foundation
import UniformTypeIdentifiers

/// The container an exported picture is written into.
///
/// The extension is derived from the format, so the file name and the encoder
/// cannot disagree about what the bytes are.
nonisolated enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case jpeg
    case heic
    case avif
    case png
    case tiff

    var id: Self { self }

    /// The picker's label. The acronyms are the same in both languages.
    var displayName: String { rawValue.uppercased() }

    /// The uniform type ImageIO writes.
    ///
    /// AVIF has no static `UTType` member in this SDK, so the identifier is
    /// looked up.
    var utType: UTType {
        switch self {
        case .jpeg: .jpeg
        case .heic: .heic
        case .avif: UTType("public.avif") ?? UTType(filenameExtension: "avif") ?? .image
        case .png: .png
        case .tiff: .tiff
        }
    }

    /// The extension the exported file carries. JPEG uses `.jpg`.
    var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .heic: "heic"
        case .avif: "avif"
        case .png: "png"
        case .tiff: "tiff"
        }
    }

    var isLossy: Bool {
        switch self {
        case .jpeg, .heic, .avif: true
        case .png, .tiff: false
        }
    }
}

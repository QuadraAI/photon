//
//  PhotoExportError.swift
//  Photon
//

import Foundation

/// Why Photon could not export a photo.
nonisolated enum PhotoExportError: Error, Equatable, Sendable {
    /// The source could not be decoded, or was gone.
    case unreadable

    /// The destination could not be created, or finalising it failed.
    case couldNotEncode

    /// The folder could not be written to: no permission, no space, or no folder.
    case couldNotWrite

    /// The user asked to stop.
    case cancelled
}

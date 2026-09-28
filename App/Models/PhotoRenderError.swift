//
//  PhotoRenderError.swift
//  Photon
//

import Foundation

/// Why Photon could not decode a photo for display.
nonisolated enum PhotoRenderError: Error, Equatable, Sendable {
    /// The file is missing, corrupt, or in a format ImageIO cannot decode.
    case unreadable
}

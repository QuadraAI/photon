//
//  PhotoRendering.swift
//  Photon
//

import CoreGraphics
import Foundation

/// Decodes a photo for display.
///
/// Previews only: AGENT.md calls for a downsampled preview and full resolution
/// on export, so nothing here ever decodes at native size.
protocol PhotoRendering: Sendable {
    /// A downsampled copy of the photo, no larger than `maxPixelSize` on its
    /// longest edge and already rotated to match its EXIF orientation.
    ///
    /// - Throws: ``PhotoRenderError/unreadable`` when the file cannot be decoded.
    func preview(for url: URL, maxPixelSize: Int) async throws(PhotoRenderError) -> CGImage
}

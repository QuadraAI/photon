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
    /// The preview the file carries inside it, decoded as it is.
    ///
    /// Costs about a millisecond, and is the reason a click puts a picture on the
    /// canvas at once instead of after a decode. It can be far smaller than
    /// `maxPixelSize`: it is a stand-in for the photo, never the photo.
    ///
    /// - Throws: ``PhotoRenderError/unreadable`` when the file cannot be read.
    func draft(for url: URL, maxPixelSize: Int) async throws(PhotoRenderError) -> CGImage

    /// A downsampled copy of the photo, no larger than `maxPixelSize` on its
    /// longest edge and already rotated to match its EXIF orientation.
    ///
    /// - Throws: ``PhotoRenderError/unreadable`` when the file cannot be decoded.
    func preview(for url: URL, maxPixelSize: Int) async throws(PhotoRenderError) -> CGImage
}

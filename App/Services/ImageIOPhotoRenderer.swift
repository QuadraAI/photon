//
//  ImageIOPhotoRenderer.swift
//  Photon
//

import CoreGraphics
import Foundation
import ImageIO
import os
import UniformTypeIdentifiers

/// ``PhotoRendering`` backed by ImageIO.
///
/// ImageIO rather than `CIImage` because nothing here applies an edit — it only
/// produces a display-sized copy. The editing pipeline that replaces this lands
/// with the first tool.
actor ImageIOPhotoRenderer: PhotoRendering {
    private let logger = Logger(subsystem: "com.quadra.Photon", category: "PhotoRenderer")

    func preview(for url: URL, maxPixelSize: Int) async throws(PhotoRenderError) -> CGImage {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
            logger.error("No image source for \(url.path(percentEncoded: false))")
            throw .unreadable
        }

        let options: [CFString: Any] = [
            // Decode even if the file carries no embedded thumbnail.
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Bake in the EXIF orientation, otherwise portrait photos from a
            // camera arrive sideways.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]

        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            logger.error("Could not decode \(url.path(percentEncoded: false))")
            throw .unreadable
        }

        return image
    }
}

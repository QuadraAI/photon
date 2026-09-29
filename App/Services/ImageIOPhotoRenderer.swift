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
///
/// Where the pixels come from is what makes a click cheap: a camera file carries
/// its own preview, and reading that takes about a millisecond where decoding the
/// picture takes 80 ms for a JPEG and 700 ms for a raw.
actor ImageIOPhotoRenderer: PhotoRendering {
    private let logger = Logger(subsystem: "com.quadra.Photon", category: "PhotoRenderer")

    /// The last draft handed out, so the full decode can build on it rather than
    /// read the same preview twice for one click.
    private var lastDraft: (url: URL, maxPixelSize: Int, image: CGImage)?

    func draft(for url: URL, maxPixelSize: Int) async throws(PhotoRenderError) -> CGImage {
        let image = try thumbnail(for: url, maxPixelSize: maxPixelSize, from: .embedded)
        lastDraft = (url, maxPixelSize, image)
        return image
    }

    func preview(for url: URL, maxPixelSize: Int) async throws(PhotoRenderError) -> CGImage {
        // A superseded click should not be decoded at all: the caller checks
        // `isCancelled` and drops whatever comes back.
        guard !Task.isCancelled else { throw .unreadable }

        // For a camera file the draft *is* the picture — its preview is a
        // full-size JPEG, and decoding the raw instead would cost thirty times as
        // much to arrive at something the canvas cannot tell apart.
        if let lastDraft,
           lastDraft.url == url,
           lastDraft.maxPixelSize == maxPixelSize,
           isDisplaySized(lastDraft.image, for: maxPixelSize) {
            return lastDraft.image
        }

        if let embedded = try? thumbnail(for: url, maxPixelSize: maxPixelSize, from: .embedded),
           isDisplaySized(embedded, for: maxPixelSize) {
            return embedded
        }

        return try thumbnail(for: url, maxPixelSize: maxPixelSize, from: .picture)
    }

    // MARK: - ImageIO

    /// Where a thumbnail's pixels come from.
    private enum Source {
        /// The preview the file carries, which a camera writes beside the picture
        /// so a viewer does not have to decode a raw.
        case embedded
        /// The picture itself.
        case picture
    }

    private func thumbnail(
        for url: URL,
        maxPixelSize: Int,
        from origin: Source
    ) throws(PhotoRenderError) -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else {
            logger.error("No image source for \(url.path(percentEncoded: false))")
            throw .unreadable
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: origin == .picture,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: origin == .embedded,
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

    /// Whether an image is worth showing as the photo rather than as a stand-in:
    /// half the size asked for, which still accepts the 1024-pixel preview a
    /// smaller camera file carries.
    private func isDisplaySized(_ image: CGImage, for maxPixelSize: Int) -> Bool {
        max(image.width, image.height) * 2 >= maxPixelSize
    }
}

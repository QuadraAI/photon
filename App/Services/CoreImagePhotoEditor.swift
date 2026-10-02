//
//  CoreImagePhotoEditor.swift
//  Photon
//

import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Metal
import os

/// ``PhotoEditing`` backed by ImageIO for the decode and Core Image for the recipe.
///
/// ImageIO still produces the pixels: a camera file carries its own preview, and
/// reading that takes about a millisecond where decoding the picture takes 80 ms
/// for a JPEG and 700 ms for a raw. Nothing about a crop needs to be decoded at
/// any size other than the one it is shown at, so the cheap path stays.
///
/// Core Image applies the recipe, which is where the editing pipeline lives. Its
/// stage order is a specification rather than a detail, and this is it:
///
///     decode (ImageIO, EXIF orientation baked in)
///       → turn
///       → crop
///       → render
///
/// Geometry last, and turn before crop. Every editor that has colour stages
/// agrees on this shape — darktable's pixelpipe and Lightroom's develop pipeline
/// both put geometry at the end — because a tonal stage that ran on a cropped
/// image would measure the crop rather than the photo, and two crops of the same
/// picture would come out differently graded. There is nothing to order yet;
/// there will be, and the order is cheaper to write down now than to discover.
///
/// When the tonal tools land, the base decode moves from the thumbnail below to a
/// `CIImage` read from the file — `CIRAWFilter` for a raw — and this comment
/// becomes the list of stages between the decode and the turn. It is one function.
actor CoreImagePhotoEditor: PhotoEditing {
    private let logger = Logger(subsystem: "com.quadra.Photon", category: "PhotoEditor")

    /// One context for the app, built once here and handed to every window.
    ///
    /// A `CIContext` caches compiled kernels and intermediate buffers, so a second
    /// one costs a second compile and gives nothing back. Created in the
    /// composition root and injected, rather than reached for as a singleton.
    private let context: CIContext

    /// The last draft handed out, so the full decode can build on it rather than
    /// read the same preview twice for one click.
    private var lastDraft: (url: URL, maxPixelSize: Int, image: CGImage)?

    init() {
        // Metal where there is a device, the CPU otherwise — a simulator, or a
        // machine whose GPU is unavailable. Falling back keeps the app working
        // rather than failing to launch for a reason the user cannot act on.
        if let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device)
        } else {
            logger.notice("No Metal device; rendering through the CPU context")
            context = CIContext()
        }
    }

    // MARK: - PhotoEditing

    func draft(for url: URL, maxPixelSize: Int) async throws(PhotoRenderError) -> CGImage {
        let image = try thumbnail(for: url, maxPixelSize: maxPixelSize, from: .embedded)
        lastDraft = (url, maxPixelSize, image)
        return image
    }

    func render(_ url: URL, recipe: EditRecipe, maxPixelSize: Int?) async throws(PhotoRenderError) -> CGImage {
        // A superseded click or a superseded crop should not be decoded at all:
        // the caller checks `isCancelled` and drops whatever comes back.
        guard !Task.isCancelled else { throw .unreadable }

        let sourceSize = try uprightSize(of: url)
        let limit = maxPixelSize ?? Int(max(sourceSize.width, sourceSize.height))
        let decoded = try decoded(url, maxPixelSize: limit)

        let crop = recipe.crop
        guard !crop.isIdentity else { return decoded }

        var image = CIImage(cgImage: decoded)
        if crop.rotation != .none {
            // `oriented(_:)` rather than a transform: it re-derives the extent,
            // where a rotation of a quarter turn about the origin leaves the
            // picture sitting outside its own bounds.
            image = image.oriented(crop.rotation.orientation)
        }

        let extent = image.extent
        let frame = CropGeometry.turnedSize(sourceSize, by: crop.rotation)
        let rect = CropGeometry.coreImageRect(crop.rect, frame: frame, extent: extent).integral

        let cropped = image.cropped(to: rect)
        // `cropped(to:)` keeps the crop where it was in the parent, so what is
        // left is the same size as the photo with everything outside the rect
        // transparent. Moving it back to the origin is what makes the render the
        // size of the crop.
        let placed = cropped.transformed(
            by: CGAffineTransform(translationX: -cropped.extent.minX, y: -cropped.extent.minY)
        )

        let rendered = context.createCGImage(
            placed,
            from: placed.extent,
            format: .RGBA8,
            colorSpace: decoded.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        ) ?? context.createCGImage(placed, from: placed.extent)

        guard let rendered else {
            logger.error("Could not render \(url.path(percentEncoded: false))")
            throw .unreadable
        }

        return rendered
    }

    func pixelSize(of url: URL) async throws(PhotoRenderError) -> CGSize {
        try uprightSize(of: url)
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

    /// The photo's own size, with its EXIF orientation applied.
    ///
    /// A property read rather than a decode: no pixels are touched, which is what
    /// lets the crop maths ask for it on every drag without costing anything.
    private func uprightSize(of url: URL) throws(PhotoRenderError) -> CGSize {
        guard let source = CGImageSourceCreateWithURL(
            url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ), let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
            let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
            width > 0, height > 0
        else {
            logger.error("No image properties for \(url.path(percentEncoded: false))")
            throw .unreadable
        }

        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)
            .flatMap { CGImagePropertyOrientation(rawValue: $0.uint32Value) } ?? .up

        return CropGeometry.uprightSize(CGSize(width: width, height: height), for: orientation)
    }

    /// A display-sized copy of the photo, upright and with no recipe applied.
    ///
    /// For a camera file the draft *is* the picture — its preview is a full-size
    /// JPEG, and decoding the raw instead would cost thirty times as much to
    /// arrive at something the canvas cannot tell apart.
    private func decoded(_ url: URL, maxPixelSize: Int) throws(PhotoRenderError) -> CGImage {
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

    private func thumbnail(
        for url: URL,
        maxPixelSize: Int,
        from origin: Source
    ) throws(PhotoRenderError) -> CGImage {
        guard let source = CGImageSourceCreateWithURL(
            url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else {
            logger.error("No image source for \(url.path(percentEncoded: false))")
            throw .unreadable
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: origin == .picture,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: origin == .embedded,
            // Bake in the EXIF orientation, otherwise portrait photos from a
            // camera arrive sideways — and the crop, which is normalized to the
            // frame the user can see, would be taken from the wrong one.
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

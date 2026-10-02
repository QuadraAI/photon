//
//  CoreImagePhotoEditor.swift
//  Photon
//

import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
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
///       → colour: cast, vibrance, saturation, bands
///       → turn
///       → crop
///       → render
///
/// Geometry last, and turn before crop. Every editor that has colour stages
/// agrees on this shape — darktable's pixelpipe and Lightroom's develop pipeline
/// both put geometry at the end — because a tonal stage that ran on a cropped
/// image would measure the crop rather than the photo, and two crops of the same
/// picture would come out differently graded.
///
/// Within the colour stages the order is the panel's, top to bottom: a cast is
/// taken out of the photo before anything is measured against it, the two global
/// sliders act on every colour, and the eight bands act last, on the colours the
/// user can see by then.
///
/// The context works in the colour space Core Image defaults to — an extended
/// *linear* sRGB, which is what Apple's own filters are built for and what makes
/// a per-channel gain a white balance. The band maths is the one stage that
/// needs a gamma-encoded space, and it converts for itself.
actor CoreImagePhotoEditor: PhotoEditing {
    private let logger = Logger(subsystem: "com.quadra.Photon", category: "PhotoEditor")

    /// One context for the app, built once here and handed to every window.
    ///
    /// A `CIContext` caches compiled kernels and intermediate buffers, so a second
    /// one costs a second compile and gives nothing back. Created in the
    /// composition root and injected, rather than reached for as a singleton.
    ///
    /// Not private, because it is also what draws: a staged preview is handed to
    /// a Metal view along with this, and the view renders it with the context
    /// that built it.
    nonisolated let context: CIContext

    /// The band maths, compiled once. Nil on a machine with no Metal device,
    /// where the three global sliders still work and the bands go quiet.
    private let colorKernel: CIColorKernel?

    /// The last draft handed out, so the full decode can build on it rather than
    /// read the same preview twice for one click.
    private var lastDraft: (url: URL, maxPixelSize: Int, image: CGImage)?

    /// The last photo's measured cast, so a slider drag measures it once rather
    /// than on every frame.
    private var lastCast: (url: URL, gains: SIMD3<Double>)?

    /// Longest edge of the decode the colour cast is measured from.
    ///
    /// Fixed, rather than the size of the render underway: the correction has to
    /// come out the same at preview size as at export, and an average taken over
    /// a different set of pixels would not.
    private static let castSampleSize = 256

    /// How far a channel may be pushed to take a cast out.
    ///
    /// A photo that is one colour throughout — a frame filled by a leaf — would
    /// otherwise ask for an unbounded correction.
    private static let castGainRange: ClosedRange<Double> = 0.5...2

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

        colorKernel = ColorKernel.make()
    }

    // MARK: - PhotoEditing

    func draft(for url: URL, maxPixelSize: Int) async throws(PhotoRenderError) -> CGImage {
        let image = try thumbnail(for: url, maxPixelSize: maxPixelSize, from: .embedded)
        lastDraft = (url, maxPixelSize, image)
        return image
    }

    func render(_ url: URL, recipe: EditRecipe, maxPixelSize: Int?) async throws(PhotoRenderError) -> CGImage {
        let staged = try await staged(url, recipe: recipe, maxPixelSize: maxPixelSize)

        // Nothing was asked of the photo, so the file's own pixels come back
        // rather than a copy of them that has been through a context and back.
        if let decoded = staged.decoded { return decoded }

        let rendered = context.createCGImage(
            staged.image,
            from: staged.image.extent,
            format: .RGBA8,
            colorSpace: staged.colorSpace
        ) ?? context.createCGImage(staged.image, from: staged.image.extent)

        guard let rendered else {
            logger.error("Could not render \(url.path(percentEncoded: false))")
            throw .unreadable
        }

        return rendered
    }

    func preview(_ url: URL, recipe: EditRecipe, maxPixelSize: Int?) async throws(PhotoRenderError) -> CIImage {
        try await staged(url, recipe: recipe, maxPixelSize: maxPixelSize).image
    }

    // MARK: - The pipeline

    /// A photo with the recipe's stages applied, and not yet drawn.
    ///
    /// The whole of the pipeline bar the last step, shared by the two ways out
    /// of it: ``render(_:recipe:maxPixelSize:)`` asks this for pixels and
    /// ``preview(_:recipe:maxPixelSize:)`` hands what comes back to a view. One
    /// function, so the stage order is stated once however the photo leaves.
    private struct Staged {
        /// What Core Image will draw.
        let image: CIImage

        /// The decode itself, when nothing was asked of the photo.
        ///
        /// Kept so that a recipe that is not an edit can be answered with the
        /// file's own pixels rather than a copy of them.
        let decoded: CGImage?

        /// The space the result belongs in, which is the file's own.
        let colorSpace: CGColorSpace
    }

    private func staged(
        _ url: URL,
        recipe: EditRecipe,
        maxPixelSize: Int?
    ) async throws(PhotoRenderError) -> Staged {
        // A superseded click or a superseded crop should not be decoded at all:
        // the caller checks `isCancelled` and drops whatever comes back.
        guard !Task.isCancelled else { throw .unreadable }

        let sourceSize = try uprightSize(of: url)
        let limit = maxPixelSize ?? Int(max(sourceSize.width, sourceSize.height))
        let decoded = try decoded(url, maxPixelSize: limit)
        let colorSpace = decoded.colorSpace ?? CGColorSpaceCreateDeviceRGB()

        let color = recipe.color
        let crop = recipe.crop
        guard !color.isIdentity || !crop.isIdentity else {
            return Staged(image: CIImage(cgImage: decoded), decoded: decoded, colorSpace: colorSpace)
        }

        var image = CIImage(cgImage: decoded)
        if !color.isIdentity {
            image = coloured(image, with: color, of: url)
        }

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

        return Staged(image: placed, decoded: nil, colorSpace: colorSpace)
    }

    func pixelSize(of url: URL) async throws(PhotoRenderError) -> CGSize {
        try uprightSize(of: url)
    }

    // MARK: - Colour

    /// The photo with the colour tool's stages applied.
    ///
    /// Every stage is skipped when it is not asked for, so a photo with only a
    /// cast correction never pays for the kernel, and one with only a band shift
    /// never pays for the measurement.
    private func coloured(_ image: CIImage, with color: ColorAdjustments, of url: URL) -> CIImage {
        var image = image

        if color.colorCast > 0, let gains = castGains(of: url) {
            image = Self.balanced(image, by: gains, amount: color.colorCast)
        }

        if color.vibrance != 0 {
            let vibrance = CIFilter.vibrance()
            vibrance.inputImage = image
            vibrance.amount = Float(color.vibrance)
            image = vibrance.outputImage ?? image
        }

        if color.saturation != 0 {
            let controls = CIFilter.colorControls()
            controls.inputImage = image
            // −1 is grey and +1 is twice the colour, which is what a saturation
            // slider is expected to do at its ends.
            controls.saturation = Float(1 + color.saturation)
            image = controls.outputImage ?? image
        }

        if color.hasBandShift, let colorKernel,
           let banded = ColorKernel.apply(color, to: image, using: colorKernel) {
            image = banded
        }

        return image
    }

    /// How far each channel has to move to take the photo's own cast out.
    ///
    /// Grey-world: the average of the whole photo should be neutral, so the
    /// correction is whatever brings it there. Measured from a fixed-size decode
    /// rather than from whatever the render is working at, because the preview
    /// and the export have to agree on the correction.
    ///
    /// The average is the whole of the estimate, and it is a blunt one: a sunset,
    /// or a frame filled by one colour, is legitimately not neutral and this
    /// pulls it toward grey anyway. The slider's default is off, which is where a
    /// photo like that should stay. `CIAreaAverage` is the piece to replace when
    /// a better estimate arrives; nothing else has to move.
    private func castGains(of url: URL) -> SIMD3<Double>? {
        if let lastCast, lastCast.url == url { return lastCast.gains }

        guard let sample = try? thumbnail(for: url, maxPixelSize: Self.castSampleSize, from: .picture) else {
            logger.error("Could not sample \(url.path(percentEncoded: false)) to measure its colour cast")
            return nil
        }

        let average = CIFilter.areaAverage()
        average.inputImage = CIImage(cgImage: sample)
        average.extent = CGRect(x: 0, y: 0, width: sample.width, height: sample.height)
        guard let averaged = average.outputImage else { return nil }

        var pixel = [Float](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            context.render(
                averaged,
                toBitmap: base,
                rowBytes: MemoryLayout<Float>.size * 4,
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                // No colour matching, so what comes back is the working space's
                // own numbers — which is the space the gains are applied in.
                format: .RGBAf,
                colorSpace: nil
            )
        }

        let mean = SIMD3(Double(pixel[0]), Double(pixel[1]), Double(pixel[2]))
        let neutral = (mean.x + mean.y + mean.z) / 3
        guard neutral > 0 else { return nil }

        // A channel that is already at zero cannot be brought up by a multiplier,
        // so it asks for the most the range allows and the clamp answers.
        func gain(_ channel: Double) -> Double {
            guard channel > 1e-5 else { return Self.castGainRange.upperBound }
            return (neutral / channel).clamped(to: Self.castGainRange)
        }

        let gains = SIMD3(gain(mean.x), gain(mean.y), gain(mean.z))
        lastCast = (url, gains)
        return gains
    }

    /// The photo with each channel moved `amount` of the way to its gain.
    ///
    /// Applied in the working space, which is linear: a white balance multiplies
    /// light. The same multiplication on gamma-encoded values would correct by a
    /// different amount in the shadows than in the highlights.
    private static func balanced(_ image: CIImage, by gains: SIMD3<Double>, amount: Double) -> CIImage {
        func scaled(_ gain: Double) -> CGFloat { CGFloat(1 + amount * (gain - 1)) }

        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = image
        matrix.rVector = CIVector(x: scaled(gains.x), y: 0, z: 0, w: 0)
        matrix.gVector = CIVector(x: 0, y: scaled(gains.y), z: 0, w: 0)
        matrix.bVector = CIVector(x: 0, y: 0, z: scaled(gains.z), w: 0)
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        matrix.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        return matrix.outputImage ?? image
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

        // A RAW goes through Core Image's own RAW pipeline rather than ImageIO's
        // generic decode. Apple tunes the demosaic, the noise reduction and the
        // lens correction for each of the hundreds of camera models it knows,
        // and none of that is in the generic path.
        if let raw = rawImage(url, maxPixelSize: maxPixelSize) {
            return raw
        }

        return try thumbnail(for: url, maxPixelSize: maxPixelSize, from: .picture)
    }

    /// The file decoded by the RAW pipeline, or nil when it is not a RAW.
    ///
    /// The file decides which path it takes rather than a list of extensions
    /// kept here: `CIFilter(imageURL:options:)` returns a `CIRAWFilter` for a RAW
    /// and something else for a JPEG, so the cast *is* the question.
    ///
    /// `scaleFactor` is what makes this affordable. Core Image renders the photo
    /// at that fraction of its native size, so a preview asks for the fraction
    /// that fills the canvas and an export asks for 1 — the whole of the file,
    /// which is the only place a RAW should ever be decoded at full size.
    private func rawImage(_ url: URL, maxPixelSize: Int) -> CGImage? {
        guard let filter = CIFilter(imageURL: url, options: nil) as? CIRAWFilter else { return nil }

        let native = filter.nativeSize
        guard native.width > 0, native.height > 0 else { return nil }

        filter.scaleFactor = Float(min(1, CGFloat(maxPixelSize) / max(native.width, native.height)))

        guard let image = filter.outputImage,
              let colourSpace = image.colorSpace
                ?? CGColorSpace(name: CGColorSpace.sRGB)
                ?? CGColorSpaceCreateDeviceRGB() as CGColorSpace?
        else { return nil }

        return context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: colourSpace)
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

//
//  CoreImagePhotoEditorTests.swift
//  PhotonTests
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import Photon

/// The engine, against real files.
///
/// Sizes alone catch most of what can go wrong here — a normalized rect read as
/// pixels is off by the frame's aspect every time, and a crop that forgot to move
/// back to the origin comes back the size of the whole photo. But a crop can also
/// be the right size and the wrong *place*, and the only way to see that is to
/// look at the pixels. The fixtures are flat colour swatches, deliberately, so
/// these write their own four-coloured one rather than change what the UI tests
/// are built on.
@Suite("Core Image photo editor")
struct CoreImagePhotoEditorTests {
    private let editor = CoreImagePhotoEditor()

    /// `alpha.png`: 64×48, so 4:3 and every size below comes out whole.
    private var landscape: URL { Self.fixture("alpha.png") }

    /// `beta.png`: 48×64, the same photo the other way up.
    private var portrait: URL { Self.fixture("beta.png") }

    /// `gamma.png`: 32×32, where a ratio has nothing to decide.
    private var square: URL { Self.fixture("Subfolder/gamma.png") }

    // MARK: - Identity

    @Test("A photo with nothing done to it comes back at the size it was asked for")
    func identityRendersThePhoto() async throws {
        let image = try await editor.render(landscape, recipe: .identity, maxPixelSize: 2048)

        #expect(image.width == 64)
        #expect(image.height == 48)
    }

    @Test("A small photo is not enlarged to the preview size")
    func identityDoesNotUpscale() async throws {
        let image = try await editor.render(landscape, recipe: .identity, maxPixelSize: nil)

        #expect(image.width == 64, "The preview and the export are the same photo at its own size")
        #expect(image.height == 48)
    }

    @Test("The reported size is the photo's own, upright")
    func reportingTheSize() async throws {
        #expect(try await editor.pixelSize(of: landscape) == CGSize(width: 64, height: 48))
        #expect(try await editor.pixelSize(of: portrait) == CGSize(width: 48, height: 64))
        #expect(try await editor.pixelSize(of: square) == CGSize(width: 32, height: 32))
    }

    @Test("A file that is not an image cannot be rendered, and says so")
    func unreadableFilesThrow() async {
        let missing = Self.fixture("does-not-exist.png")

        await #expect(throws: PhotoRenderError.unreadable) {
            try await editor.render(missing, recipe: .identity, maxPixelSize: 512)
        }
        await #expect(throws: PhotoRenderError.unreadable) {
            _ = try await editor.pixelSize(of: missing)
        }
    }

    // MARK: - Cropping

    @Test("A full-frame 16:9 crop takes the pixels the ratio asks for")
    func croppingToARatio() async throws {
        let rect = CropGeometry.fitted(.fixed(width: 16, height: 9), inside: CropGeometry.unitFrame, frame: CGSize(width: 64, height: 48))
        let image = try await editor.render(
            landscape,
            recipe: EditRecipe(crop: Crop(rect: rect, aspect: .fixed(width: 16, height: 9), rotation: .none)),
            maxPixelSize: 2048
        )

        #expect(image.width == 64)
        #expect(image.height == 36)
    }

    @Test("The same recipe gives the same photo at preview size and at full size")
    func previewAndExportAgree() async throws {
        // The whole reason a crop is stored normalized rather than in pixels.
        let crop = Crop(
            rect: CGRect(x: 0.25, y: 0.125, width: 0.5, height: 0.75),
            aspect: .free,
            rotation: .none
        )
        let recipe = EditRecipe(crop: crop)

        let preview = try await editor.render(landscape, recipe: recipe, maxPixelSize: 2048)
        let full = try await editor.render(landscape, recipe: recipe, maxPixelSize: nil)

        #expect(preview.width == full.width)
        #expect(preview.height == full.height)
        #expect(preview.width == 32)
        #expect(preview.height == 36)
    }

    @Test("A square photo's own ratio is square")
    func aSquarePhotoIsSquare() async throws {
        let rect = CropGeometry.fitted(.original, inside: CropGeometry.unitFrame, frame: CGSize(width: 32, height: 32))
        let image = try await editor.render(
            square,
            recipe: EditRecipe(crop: Crop(rect: rect, aspect: .original, rotation: .none)),
            maxPixelSize: 2048
        )

        #expect(image.width == 32)
        #expect(image.height == 32)
    }

    @Test("Turning the photo swaps which side is the width")
    func turningThePhoto() async throws {
        let recipe = EditRecipe(
            crop: Crop(rect: CropGeometry.unitFrame, aspect: .original, rotation: .clockwise)
        )
        let image = try await editor.render(landscape, recipe: recipe, maxPixelSize: 2048)

        #expect(image.width == 48)
        #expect(image.height == 64)
    }

    @Test("A quarter turn twice is the photo the right way up, for the pixels")
    func turningTwiceIsThePhotoAgain() async throws {
        let flat = try await editor.render(landscape, recipe: .identity, maxPixelSize: 2048)
        let twice = try await editor.render(
            landscape,
            recipe: EditRecipe(crop: Crop(rect: CropGeometry.unitFrame, aspect: .original, rotation: .upsideDown)),
            maxPixelSize: 2048
        )

        #expect(twice.width == flat.width)
        #expect(twice.height == flat.height)
        #expect(try bytes(of: twice) == (try bytes(of: flat)))
    }

    // MARK: - Where the crop lands

    @Test("A crop takes the corner it names, on both axes")
    func croppingLandsOnTheRightPixels() async throws {
        // The one thing a size cannot show. Top-left in the recipe means top-left
        // on screen, which means the y flip into Core Image's coordinates
        // happened exactly once.
        let file = try Self.writeQuadrants()
        defer { try? FileManager.default.removeItem(at: file) }

        let frame = CGSize(width: 16, height: 8)
        let corners: [(name: String, rect: CGRect, isExpected: ([UInt8]) -> Bool)] = [
            ("top-left", CGRect(x: 0, y: 0, width: 0.5, height: 0.5), Self.isRed),
            ("top-right", CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5), Self.isGreen),
            ("bottom-left", CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5), Self.isBlue),
            ("bottom-right", CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5), Self.isYellow),
        ]

        for corner in corners {
            let recipe = EditRecipe(crop: Crop(rect: corner.rect, aspect: .free, rotation: .none))
            let image = try await editor.render(file, recipe: recipe, maxPixelSize: 2048)

            #expect(image.width == 8, "\(corner.name): the quarter is a quarter")
            #expect(image.height == 4)

            let pixel = try firstPixel(of: image)
            #expect(corner.isExpected(pixel), "\(corner.name) came back as \(pixel)")
        }

        #expect(CropGeometry.pixelRect(CGRect(x: 0, y: 0, width: 0.5, height: 0.5), in: frame).width == 8)
    }

    @Test("Turning moves the region with the pixels, so a crop of a turned photo still finds it")
    func croppingAfterATurn() async throws {
        let file = try Self.writeQuadrants()
        defer { try? FileManager.default.removeItem(at: file) }

        // The top-left quarter, turned a quarter clockwise: it lands top-right.
        let recipe = EditRecipe(
            crop: Crop(
                rect: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5),
                aspect: .free,
                rotation: .clockwise
            )
        )
        let image = try await editor.render(file, recipe: recipe, maxPixelSize: 2048)

        #expect(image.width == 4)
        #expect(image.height == 8)
        #expect(Self.isRed(try firstPixel(of: image)), "The red corner followed the turn")
    }

    // MARK: - The draft

    @Test("A draft comes back, and a later render of the same size can build on it")
    func draftsAreDecoded() async throws {
        let draft = try await editor.draft(for: landscape, maxPixelSize: 2048)

        #expect(draft.width == 64)
        #expect(draft.height == 48)

        let rendered = try await editor.render(landscape, recipe: .identity, maxPixelSize: 2048)
        #expect(rendered.width == draft.width)
    }

    @Test("A draft of a file that is not an image says so rather than returning nothing")
    func draftsOfUnreadableFilesThrow() async {
        await #expect(throws: PhotoRenderError.unreadable) {
            try await editor.draft(for: Self.fixture("does-not-exist.png"), maxPixelSize: 512)
        }
    }

    // MARK: - Formats

    @Test("A TIFF decodes, reports its size, and crops like any other photo")
    func tiffIsAnImageLikeAnyOther() async throws {
        // A scanner's format and a photographer's export. Neither the size nor the
        // crop cared what container the pixels arrived in.
        let file = try Self.writeQuadrants(as: .tiff)
        defer { try? FileManager.default.removeItem(at: file) }

        #expect(try await editor.pixelSize(of: file) == CGSize(width: 16, height: 8))

        let full = try await editor.render(file, recipe: .identity, maxPixelSize: 2048)
        #expect(full.width == 16)
        #expect(full.height == 8)

        // And a crop of it lands on the corner it names, so this is the whole
        // pipeline and not just a decode.
        let recipe = EditRecipe(
            crop: Crop(rect: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5), aspect: .free, rotation: .none)
        )
        let corner = try await editor.render(file, recipe: recipe, maxPixelSize: 2048)

        #expect(corner.width == 8)
        #expect(corner.height == 4)
        #expect(Self.isGreen(try firstPixel(of: corner)))
    }

    // MARK: - Helpers

    /// A fixture from `Tests/Photos`, addressed as a plain filesystem path.
    private static func fixture(_ name: String) -> URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Photos")
            .appending(path: name)
    }

    // MARK: - A photo whose corners can be told apart

    private enum FixtureError: Error {
        case couldNotBuildTheFile
        case couldNotReadThePixels
    }

    /// Writes a 16×8 picture of four quadrants — red top-left, green top-right,
    /// blue bottom-left, yellow bottom-right — in `type`'s format.
    ///
    /// Colours named by where they are *seen*, which is the whole point — the
    /// drawing context counts y the other way, so the conversion happens here and
    /// the assertions can be about the picture.
    private static func writeQuadrants(as type: UTType = .png) throws -> URL {
        let size = CGSize(width: 16, height: 8)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: Int(size.width),
                height: Int(size.height),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { throw FixtureError.couldNotBuildTheFile }

        /// Fills a rectangle given by its place in the picture.
        func fill(_ colour: CGColor, left: CGFloat, top: CGFloat) {
            context.setFillColor(colour)
            context.fill(
                CGRect(
                    x: left,
                    y: size.height - top - size.height / 2,
                    width: size.width / 2,
                    height: size.height / 2
                )
            )
        }

        let red = CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        let green = CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)
        let blue = CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
        let yellow = CGColor(srgbRed: 1, green: 1, blue: 0, alpha: 1)

        fill(red, left: 0, top: 0)
        fill(green, left: size.width / 2, top: 0)
        fill(blue, left: 0, top: size.height / 2)
        fill(yellow, left: size.width / 2, top: size.height / 2)

        guard let image = context.makeImage() else { throw FixtureError.couldNotBuildTheFile }

        let suffix = type.preferredFilenameExtension ?? "png"
        let url = FileManager.default.temporaryDirectory
            .appending(path: "photon-editor-test-\(UUID().uuidString).\(suffix)")
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            type.identifier as CFString,
            1,
            nil
        ) else { throw FixtureError.couldNotBuildTheFile }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw FixtureError.couldNotBuildTheFile }

        return url
    }

    /// Every pixel of an image, as bytes, so two renders can be compared.
    private func bytes(of image: CGImage) throws -> [UInt8] {
        let width = image.width
        let height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)

        try data.withUnsafeMutableBytes { buffer in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                    data: buffer.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else { throw FixtureError.couldNotReadThePixels }

            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        return data
    }

    /// The first pixel's red, green and blue.
    private func firstPixel(of image: CGImage) throws -> [UInt8] {
        Array(try bytes(of: image).prefix(3))
    }

    // Predicates rather than exact values: the file round-trips through sRGB, and
    // what is being tested is which corner came back, not the arithmetic of 255.
    private static func isRed(_ pixel: [UInt8]) -> Bool { pixel[0] > 200 && pixel[1] < 60 && pixel[2] < 60 }
    private static func isGreen(_ pixel: [UInt8]) -> Bool { pixel[0] < 60 && pixel[1] > 200 && pixel[2] < 60 }
    private static func isBlue(_ pixel: [UInt8]) -> Bool { pixel[0] < 60 && pixel[1] < 60 && pixel[2] > 200 }
    private static func isYellow(_ pixel: [UInt8]) -> Bool { pixel[0] > 200 && pixel[1] > 200 && pixel[2] < 60 }
}

//
//  PreviewStagingTests.swift
//  PhotonTests
//

import CoreGraphics
import CoreImage
import Foundation
import Testing

@testable import Photon

/// The two ways out of the pipeline: a description for the canvas, and pixels for
/// an export.
///
/// They are one function underneath — the staging that applies the recipe's
/// stages and stops short of drawing — and these are what hold them to it. A
/// canvas that disagreed with the export would be a lie about what the file is
/// going to look like, which is the one thing a non-destructive editor cannot
/// afford. A staged preview that did not carry its size would be a canvas laid
/// out wrong, since the canvas measures the picture by its extent rather than by
/// anything the file says.
@Suite("Preview staging")
struct PreviewStagingTests {
    private let editor = CoreImagePhotoEditor()

    /// `alpha.png`: 64×48, so every size below comes out whole.
    private static func fixture(_ name: String) -> URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Photos")
            .appending(path: name)
    }

    @Test("A staged preview is the size it was asked for, and says so")
    func previewIsTheSizeAskedFor() async throws {
        let preview = try await editor.preview(Self.fixture("alpha.png"), recipe: .identity, maxPixelSize: 32)

        #expect(preview.extent.size == CGSize(width: 32, height: 24))
    }

    @Test("A photo with nothing done to it stages at its own size")
    func identityStagesWhole() async throws {
        let preview = try await editor.preview(Self.fixture("alpha.png"), recipe: .identity, maxPixelSize: nil)

        #expect(preview.extent.size == CGSize(width: 64, height: 48))
    }

    @Test("A staged preview and a render of the same recipe are the same picture")
    func previewAndRenderAgree() async throws {
        var colour = ColorAdjustments()
        colour.saturation = 0.4
        colour[.luminance, in: .green] = -0.5
        let recipe = EditRecipe(crop: .identity, color: colour)

        let url = Self.fixture("alpha.png")
        let preview = try await editor.preview(url, recipe: recipe, maxPixelSize: 64)
        let rendered = try await editor.render(url, recipe: recipe, maxPixelSize: 64)

        #expect(preview.extent.size == CGSize(width: rendered.width, height: rendered.height))

        // One pixel, drawn both ways: the canvas draws the first and an export
        // writes the second, so a difference here is the canvas lying about the
        // file. A step of one is the eight bits both of them end in.
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let spot = CGRect(x: 32, y: 24, width: 1, height: 1)
        var staged = [UInt8](repeating: 0, count: 4)
        var flat = [UInt8](repeating: 0, count: 4)

        editor.context.render(preview, toBitmap: &staged, rowBytes: 4, bounds: spot, format: .RGBA8, colorSpace: space)
        editor.context.render(
            CIImage(cgImage: rendered),
            toBitmap: &flat,
            rowBytes: 4,
            bounds: spot,
            format: .RGBA8,
            colorSpace: space
        )

        let worst = zip(staged, flat).map { abs(Int($0) - Int($1)) }.max() ?? 0
        #expect(worst <= 1, "The canvas reads \(staged) where the export reads \(flat)")
    }
}

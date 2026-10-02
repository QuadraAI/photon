//
//  StagedPhotoViewTests.swift
//  PhotonTests
//

import CoreGraphics
import CoreImage
import Foundation
import Metal
import Testing

@testable import Photon

/// How a staged picture is fitted to the drawable it is drawn in.
///
/// The one piece of the canvas that can be got wrong without anything failing:
/// the picture is put on the GPU by the view, so a preview drawn at the wrong
/// size is a preview nothing in the suite notices. It was — scaled by the
/// display's factor rather than by the picture's own size, which drew it two or
/// three times the size of the view holding it and showed a quarter of the photo
/// in a corner.
@Suite("Staged photo view")
struct StagedPhotoViewTests {
    /// A picture of `size`, with nothing in it.
    private func picture(_ size: CGSize) -> CIImage {
        CIImage(color: .gray).cropped(to: CGRect(origin: .zero, size: size))
    }

    @Test("A picture is drawn at the size of the drawable, whatever the display is")
    func thePictureFillsTheDrawable() {
        // A 2048-pixel preview in a 900-point view: on a 2× display the drawable
        // is 1800 pixels across, and the picture belongs at 1800 rather than at
        // 4096.
        let image = picture(CGSize(width: 2048, height: 1536))
        let drawable = CGSize(width: 1800, height: 1350)

        let drawn = StagedPhotoView.scale(of: image, in: drawable) * image.extent.width

        #expect(drawn == 1800, "The picture was drawn \(drawn) pixels wide in an \(drawable.width) pixel drawable")
    }

    @Test("A picture smaller than the drawable is scaled up to it, and a larger one down")
    func theScaleGoesBothWays() {
        let small = picture(CGSize(width: 600, height: 400))
        let large = picture(CGSize(width: 4000, height: 2667))
        let drawable = CGSize(width: 1200, height: 800)

        #expect(StagedPhotoView.scale(of: small, in: drawable) == 2)
        #expect(StagedPhotoView.scale(of: large, in: drawable) == 0.3)
    }

    @Test("A drawable with no size yet asks for no scaling")
    func anEmptyDrawableScalesByOne() {
        // Before layout the view has no size, and dividing by it would be a
        // picture of nothing at an infinite size.
        #expect(StagedPhotoView.scale(of: picture(CGSize(width: 100, height: 100)), in: .zero) == 1)
    }

    @Test("A picture drawn the way the canvas draws it is the picture the export writes")
    func theCanvasDrawsTheExport() async throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }

        let editor = CoreImagePhotoEditor()
        var colour = ColorAdjustments()
        colour.saturation = 0.4
        let recipe = EditRecipe(crop: .identity, color: colour)
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Photos/beta.png")

        // Drawn the canvas's way: a staged picture, the canvas's own destination,
        // and a texture with the screen's own format.
        let staged = try await editor.preview(url, recipe: recipe, maxPixelSize: 8)
        // The texture is the picture's size and not a square: a destination
        // larger than the picture leaves rows nothing was drawn into, and they
        // read back as black.
        let width = Int(staged.extent.width)
        let height = Int(staged.extent.height)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        descriptor.storageMode = .shared
        let texture = try #require(device.makeTexture(descriptor: descriptor))
        let queue = try #require(device.makeCommandQueue())
        let buffer = try #require(queue.makeCommandBuffer())

        StagedPhotoView.draw(
            staged,
            into: texture,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            commandBuffer: buffer,
            with: editor.context
        )

        // Waited for by handler rather than by `waitUntilCompleted`, which the
        // compiler will not have called from here — a test is not the place to
        // teach it otherwise.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            buffer.addCompletedHandler { _ in continuation.resume() }
            buffer.commit()
        }

        var drawn = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(
            &drawn,
            bytesPerRow: width * 4,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )

        // And read the export's way, over the whole picture: a mean is what the
        // canvas's colour handling changes — writing the engine's linear working
        // space straight to the screen took the whole photo down with it.
        let rendered = try await editor.render(url, recipe: recipe, maxPixelSize: 8)
        var flat = [UInt8](repeating: 0, count: rendered.width * rendered.height * 4)
        editor.context.render(
            CIImage(cgImage: rendered),
            toBitmap: &flat,
            rowBytes: rendered.width * 4,
            bounds: CGRect(x: 0, y: 0, width: rendered.width, height: rendered.height),
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        )

        // The colour channels, whichever order they are in.
        func mean(_ bytes: [UInt8]) -> Int {
            let total = stride(from: 0, to: bytes.count, by: 4).reduce(0) { sum, index in
                sum + Int(bytes[index]) + Int(bytes[index + 1]) + Int(bytes[index + 2])
            }
            return total / (bytes.count / 4 * 3)
        }

        let onScreen = mean(drawn)
        let exported = mean(flat)
        #expect(onScreen == exported, "The canvas drew \(onScreen) where the export has \(exported)")
    }
}

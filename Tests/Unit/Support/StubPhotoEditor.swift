//
//  StubPhotoEditor.swift
//  PhotonTests
//

import CoreGraphics
import CoreImage
import Foundation
import Synchronization

@testable import Photon

/// Scriptable ``PhotoEditing`` that decodes nothing.
final class StubPhotoEditor: PhotoEditing, Sendable {
    /// Nothing is drawn in a test, so this is a context to hand back rather than
    /// one with anything in it.
    let context = CIContext()

    private let image: Mutex<CGImage?>
    private let draftImage: Mutex<CGImage?>
    private let failure: Mutex<PhotoRenderError?>
    private let delay: Duration?
    private let size: CGSize
    private let renders = Mutex<[(url: URL, recipe: EditRecipe)]>([])
    private let drafts = Mutex<[URL]>([])

    /// - Parameters:
    ///   - draft: What the file's own preview is, when it is worth saying. Left
    ///     out, it is the photo's shape, which is what a camera usually writes.
    ///   - size: What the photo claims to be, which the crop maths works in. The
    ///     default is a 4:3 landscape — the shape of the fixture the integration
    ///     tests crop, at a size where the minimum is not a factor.
    ///   - delay: How long a render takes, so a test can hold one open while a
    ///     later selection cancels it.
    init(
        image: CGImage? = nil,
        draft: CGImage? = nil,
        size: CGSize = CGSize(width: 4000, height: 3000),
        failure: PhotoRenderError? = nil,
        delay: Duration? = nil
    ) {
        let photo = image ?? Self.makeImage(of: size)
        self.image = Mutex(photo)
        self.draftImage = Mutex(draft ?? photo)
        self.size = size
        self.failure = Mutex(failure)
        self.delay = delay
    }

    /// URLs asked for a render, in call order. A draft is not a render.
    var requestedURLs: [URL] {
        renders.withLock { $0.map(\.url) }
    }

    /// What each render was asked for, in call order.
    var renderedRecipes: [EditRecipe] {
        renders.withLock { $0.map(\.recipe) }
    }

    /// URLs asked for a draft, in call order.
    var draftURLs: [URL] {
        drafts.withLock { $0 }
    }

    /// Makes every render from here on fail.
    ///
    /// The engine failing on the way *back* — a file pulled out of a folder, a
    /// decode that runs out of memory — is a different thing from a file that
    /// could never be read, and a test that holds a picture on the canvas and
    /// then breaks the engine under it needs to say when.
    func failRenders(_ error: PhotoRenderError = .unreadable) {
        failure.withLock { $0 = error }
    }

    func draft(for url: URL, maxPixelSize: Int) async throws(PhotoRenderError) -> CGImage {
        drafts.withLock { $0.append(url) }

        // A draft is never a failure: it is the picture the file carries, and a
        // file that carries none still has the picture itself.
        guard let image = draftImage.withLock({ $0 }) else { throw .unreadable }
        return image
    }

    func render(_ url: URL, recipe: EditRecipe, maxPixelSize: Int?) async throws(PhotoRenderError) -> CGImage {
        renders.withLock { $0.append((url, recipe)) }

        // `try?` because the protocol is typed `throws(PhotoRenderError)` and so
        // cannot carry a `CancellationError`. The caller checks `isCancelled`.
        if let delay { try? await Task.sleep(for: delay) }

        if let failure = failure.withLock({ $0 }) { throw failure }
        guard let image = image.withLock({ $0 }) else { throw .unreadable }
        return image
    }

    /// The staged photo, which for a stub is the one image it was built with.
    ///
    /// Answered by rendering, so a test counting what the canvas asked for keeps
    /// counting it.
    func preview(_ url: URL, recipe: EditRecipe, maxPixelSize: Int?) async throws(PhotoRenderError) -> CIImage {
        CIImage(cgImage: try await render(url, recipe: recipe, maxPixelSize: maxPixelSize))
    }

    func pixelSize(of url: URL) async throws(PhotoRenderError) -> CGSize {
        size
    }

    /// A small image of `size`'s shape, which is all a test needs to stand in for
    /// a decoded photo.
    ///
    /// The photo's own shape rather than a bare pixel: the canvas lays the picture
    /// out from whichever image it is handed, so a stub that claimed to be 4:3 and
    /// produced a square would be describing a file whose preview does not match
    /// its picture — which is true of some files, and not of the ones under test.
    private static func makeImage(of size: CGSize) -> CGImage? {
        let scale = min(1, 64 / max(size.width, size.height, 1))
        return CGImage.sized(
            width: max(1, Int(size.width * scale)),
            height: max(1, Int(size.height * scale))
        )
    }
}

extension CGImage {
    /// A plain image of a given shape, for the tests that need a file whose
    /// preview and picture disagree about theirs.
    ///
    /// `nonisolated` because the target defaults to main-actor isolation and the
    /// stub builds its images off the main actor, as the engine it stands in for
    /// does.
    nonisolated static func sized(width: Int, height: Int) -> CGImage? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )?.makeImage()
    }
}

extension PhotoItem {
    /// Fixture used across the editor tests.
    static func fixture(name: String = "IMG_0001.heic", subfolderPath: String = "", isRAW: Bool = false) -> PhotoItem {
        PhotoItem(
            url: URL(filePath: "/tmp/Photos/\(subfolderPath.isEmpty ? "" : subfolderPath + "/")\(name)"),
            subfolderPath: subfolderPath,
            isRAW: isRAW
        )
    }
}

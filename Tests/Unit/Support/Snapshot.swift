//
//  Snapshot.swift
//  PhotonTests
//

import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Why a view stopped looking like its snapshot.
enum SnapshotMismatch: Error, CustomStringConvertible {
    case couldNotRender
    case recorded(URL)
    case differs(name: String, worst: Int, differing: Double, written: URL)

    var description: String {
        switch self {
        case .couldNotRender:
            "The view could not be rendered to an image"
        case .recorded(let url):
            """
            No snapshot for this view yet. One was recorded at \
            \(url.path(percentEncoded: false)): look at it, and if it is right copy it \
            into Tests/Unit/Snapshots/ and commit it.
            """
        case .differs(let name, let worst, let differing, let written):
            """
            \(name) does not look like \(name).png: worst channel off by \(worst), \
            \(Int(differing * 100))% of the picture past tolerance. \
            The new drawing is at \(written.path(percentEncoded: false))
            """
        }
    }
}

/// Draws a view and compares it with the snapshot committed for it.
///
/// First-party, because the library that normally does this is a dependency this
/// project does not take, and what it buys is the class of fault nothing else
/// here can see: a picture drawn at the wrong size, or in the wrong colour
/// space. Both of the canvas's bugs were that, and every other test passed
/// through both of them.
///
/// A view that cannot be rendered by `ImageRenderer` cannot be snapshotted — an
/// `MTKView` draws on the GPU and comes back blank, which is why the canvas is
/// held to its pixels by `StagedPhotoViewTests` instead.
@MainActor
enum Snapshot {
    /// How far one channel may drift before a pixel counts as different.
    ///
    /// Not zero: the same view drawn twice is not always the same bytes, and a
    /// snapshot that failed on the last bit would be a test nobody trusts.
    private static let channelTolerance = 2

    /// How much of the picture may be past that tolerance.
    private static let differingBudget = 0.002

    /// Compares `view` with the snapshot `name`, recording one if there is none.
    ///
    /// - Throws: ``SnapshotMismatch``, whose description says where the new
    ///   drawing was written so it can be looked at and ruled on.
    static func expect(
        _ view: some View,
        named name: String,
        size: CGSize,
        sourceFile: StaticString = #filePath
    ) throws {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1

        guard let drawing = renderer.cgImage, let actual = bytes(of: drawing) else {
            throw SnapshotMismatch.couldNotRender
        }

        // Read from the source tree, written to the temporary directory: a test
        // bundle runs inside the app's sandbox, which can read the project but
        // not write to it. What is recorded there is copied into
        // `Tests/Unit/Snapshots/` and committed, and is read from there after.
        let fixture = URL(filePath: "\(sourceFile)")
            .deletingLastPathComponent()
            .appending(path: "Snapshots")
            .appending(path: "\(name).png")
        let recorded = FileManager.default.temporaryDirectory.appending(path: "\(name).png")
        let replacement = FileManager.default.temporaryDirectory.appending(path: "\(name).new.png")

        guard let stored = try? Data(contentsOf: fixture),
              let expected = bytes(ofPNG: stored),
              expected.count == actual.count
        else {
            try writePNG(actual, size: size, to: recorded)
            throw SnapshotMismatch.recorded(recorded)
        }

        var worst = 0
        var differing = 0
        // Alpha included: a picture that has gone transparent is as wrong as one
        // that has gone dark.
        for (theirs, ours) in zip(expected, actual) {
            let delta = abs(Int(theirs) - Int(ours))
            worst = max(worst, delta)
            if delta > channelTolerance { differing += 1 }
        }

        let share = Double(differing) / Double(actual.count)
        guard share <= differingBudget else {
            try writePNG(actual, size: size, to: replacement)
            throw SnapshotMismatch.differs(name: name, worst: worst, differing: share, written: replacement)
        }
    }

    // MARK: - Pixels

    private static func bytes(of image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }

    private static func bytes(ofPNG data: Data) -> [UInt8]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return bytes(of: image)
    }

    private static func writePNG(_ pixels: [UInt8], size: CGSize, to url: URL) throws {
        let width = Int(size.width)
        let height = Int(size.height)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { throw SnapshotMismatch.couldNotRender }

        pixels.withUnsafeBytes { buffer in
            context.data?.copyMemory(from: buffer.baseAddress!, byteCount: buffer.count)
        }
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
              )
        else { throw SnapshotMismatch.couldNotRender }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw SnapshotMismatch.couldNotRender }
    }
}

//
//  StubPhotoRenderer.swift
//  PhotonTests
//

import CoreGraphics
import Foundation
import Synchronization

@testable import Photon

/// Scriptable ``PhotoRendering`` that decodes nothing.
final class StubPhotoRenderer: PhotoRendering, Sendable {
    private let image: Mutex<CGImage?>
    private let failure: Mutex<PhotoRenderError?>
    private let delay: Duration?
    private let requested = Mutex<[URL]>([])
    private let drafts = Mutex<[URL]>([])

    /// - Parameter delay: How long the full decode takes, so a test can hold one
    ///   render open while a later selection cancels it.
    init(image: CGImage? = nil, failure: PhotoRenderError? = nil, delay: Duration? = nil) {
        self.image = Mutex(image ?? Self.makePixel())
        self.failure = Mutex(failure)
        self.delay = delay
    }

    /// URLs asked for the full decode, in call order.
    var requestedURLs: [URL] {
        requested.withLock { $0 }
    }

    /// URLs asked for a draft, in call order.
    var draftURLs: [URL] {
        drafts.withLock { $0 }
    }

    func draft(for url: URL, maxPixelSize: Int) async throws(PhotoRenderError) -> CGImage {
        drafts.withLock { $0.append(url) }

        // A draft is never a failure: it is the picture the file carries, and a
        // file that carries none still has the picture itself.
        guard let image = image.withLock({ $0 }) else { throw .unreadable }
        return image
    }

    func preview(for url: URL, maxPixelSize: Int) async throws(PhotoRenderError) -> CGImage {
        requested.withLock { $0.append(url) }

        // `try?` because the protocol is typed `throws(PhotoRenderError)` and so
        // cannot carry a `CancellationError`. The caller checks `isCancelled`.
        if let delay { try? await Task.sleep(for: delay) }

        if let failure = failure.withLock({ $0 }) { throw failure }
        guard let image = image.withLock({ $0 }) else { throw .unreadable }
        return image
    }

    /// A 1×1 image, which is all a test needs to stand in for a decoded photo.
    private static func makePixel() -> CGImage? {
        CGContext(
            data: nil,
            width: 1,
            height: 1,
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

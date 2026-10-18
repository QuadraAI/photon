//
//  StubPhotoExporter.swift
//  PhotonTests
//

import CoreGraphics
import Foundation
import Synchronization

@testable import Photon

/// Scriptable ``PhotoExporting`` that writes nothing.
final class StubPhotoExporter: PhotoExporting, Sendable {
    private let requests = Mutex<[PhotoExportRequest]>([])
    private let failure: PhotoExportError?
    private let delay: Duration?
    private let pixelSize: CGSize
    private let byteCount: Int

    /// - Parameters:
    ///   - pixelSize: What the pretend export reports as its size.
    ///   - byteCount: What the pretend file reports as its size on disk.
    ///   - failure: An error every later export throws, or nil.
    ///   - delay: How long an export takes, so a test can hold one open while
    ///     the sheet is cancelled or a retry begins.
    init(
        pixelSize: CGSize = CGSize(width: 4000, height: 3000),
        byteCount: Int = 1_234_567,
        failure: PhotoExportError? = nil,
        delay: Duration? = nil
    ) {
        self.pixelSize = pixelSize
        self.byteCount = byteCount
        self.failure = failure
        self.delay = delay
    }

    /// Everything the sheet asked to export, in call order.
    var requested: [PhotoExportRequest] {
        requests.withLock { $0 }
    }

    func export(_ request: PhotoExportRequest) async throws(PhotoExportError) -> ExportedPhoto {
        requests.withLock { $0.append(request) }

        if let delay {
            try? await Task.sleep(for: delay)
        }

        if Task.isCancelled { throw .cancelled }
        if let failure { throw failure }

        let name = ExportFilename.fileName(baseName: request.baseName, format: request.options.format)
            ?? "export.\(request.options.format.fileExtension)"

        return ExportedPhoto(
            url: request.folder.appending(path: name),
            pixelSize: pixelSize,
            byteCount: byteCount
        )
    }
}

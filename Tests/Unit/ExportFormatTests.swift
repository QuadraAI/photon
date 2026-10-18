//
//  ExportFormatTests.swift
//  PhotonTests
//

import Testing
import UniformTypeIdentifiers

@testable import Photon

@Suite("Export formats")
struct ExportFormatTests {
    @Test("The formats Photon offers are the containers it can write")
    func cases() {
        #expect(ExportFormat.allCases.map(\.rawValue) == ["jpeg", "heic", "avif", "png", "tiff"])
    }

    @Test("The extension follows the format, with jpg for JPEG")
    func extensions() {
        #expect(ExportFormat.jpeg.fileExtension == "jpg")
        #expect(ExportFormat.heic.fileExtension == "heic")
        #expect(ExportFormat.avif.fileExtension == "avif")
        #expect(ExportFormat.png.fileExtension == "png")
        #expect(ExportFormat.tiff.fileExtension == "tiff")
    }

    @Test("Only the lossy formats take a quality")
    func lossiness() {
        #expect(ExportFormat.jpeg.isLossy)
        #expect(ExportFormat.heic.isLossy)
        #expect(ExportFormat.avif.isLossy)
        #expect(!ExportFormat.png.isLossy)
        #expect(!ExportFormat.tiff.isLossy)
    }

    @Test("AVIF resolves to an image type even without a static member")
    func avifIsAnImageType() {
        #expect(ExportFormat.avif.utType.conforms(to: .image))
    }
}

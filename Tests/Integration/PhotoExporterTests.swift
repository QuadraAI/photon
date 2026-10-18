//
//  PhotoExporterTests.swift
//  PhotonTests
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import Photon

/// The exporter, against real files.
///
/// The engine integration tests already hold the pixels; these hold the things
/// that only exist once a file is written: the container, the metadata, the
/// collision name, and the fact that a failure leaves nothing half-written.
@Suite("Photo exporter")
struct PhotoExporterTests {
    private let editor = CoreImagePhotoEditor()

    // MARK: - The file

    @Test("A JPEG export is full-resolution and readable")
    func jpegExport() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try writeSource(in: folder, name: "source.png", width: 64, height: 48)
        let exporter = PhotoExporter(renderer: editor)

        let result = try await export(
            exporter,
            source: source,
            folder: folder,
            baseName: "export",
            options: ExportOptions(format: .jpeg, quality: 0.8)
        )

        #expect(result.url.lastPathComponent == "export.jpg")
        #expect(result.pixelSize == CGSize(width: 64, height: 48))
        #expect(result.byteCount > 0)

        let imageSource = try #require(CGImageSourceCreateWithURL(result.url as CFURL, nil))
        #expect((CGImageSourceGetType(imageSource) as String?) == UTType.jpeg.identifier)
        let image = try #require(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
        #expect(image.width == 64)
        #expect(image.height == 48)
    }

    @Test("A crop and a turn decide the exported pixels")
    func cropAndTurn() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try writeSource(in: folder, name: "source.png", width: 64, height: 48)
        let exporter = PhotoExporter(renderer: editor)

        let half = Crop(
            rect: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
            aspect: .free,
            rotation: .none
        )
        let cropped = try await exporter.export(
            PhotoExportRequest(
                photo: item(source),
                recipe: EditRecipe(crop: half),
                folder: folder,
                baseName: "cropped",
                options: ExportOptions(format: .png)
            )
        )
        #expect(cropped.pixelSize == CGSize(width: 32, height: 24))

        let turned = Crop(rect: CropGeometry.unitFrame, aspect: .free, rotation: .clockwise)
        let turnedResult = try await exporter.export(
            PhotoExportRequest(
                photo: item(source),
                recipe: EditRecipe(crop: turned),
                folder: folder,
                baseName: "turned",
                options: ExportOptions(format: .png)
            )
        )
        #expect(turnedResult.pixelSize == CGSize(width: 48, height: 64))
    }

    @Test("Every format ImageIO can write comes back as that type")
    func formats() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try writeSource(in: folder, name: "source.png", width: 64, height: 48)
        let exporter = PhotoExporter(renderer: editor)

        for format in ExportFormat.allCases {
            let result = try await export(
                exporter,
                source: source,
                folder: folder,
                baseName: format.rawValue,
                options: ExportOptions(format: format, quality: 0.8)
            )

            #expect(result.url.pathExtension == format.fileExtension)
            let imageSource = try #require(CGImageSourceCreateWithURL(result.url as CFURL, nil))
            #expect(
                (CGImageSourceGetType(imageSource) as String?) == format.utType.identifier,
                "\(format.rawValue) was written as another type"
            )
            #expect(result.pixelSize == CGSize(width: 64, height: 48))
        }

        let contents = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        #expect(
            !contents.contains { $0.hasPrefix(".photon-") },
            "An export left a temporary or ImageIO sidecar file in the destination"
        )
    }

    @Test("Compression quality changes a lossy file's size")
    func lossyQuality() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try writeSource(in: folder, name: "noise.png", width: 256, height: 256, noise: true)
        let exporter = PhotoExporter(renderer: editor)

        for format in ExportFormat.allCases where format.isLossy {
            let low = try await export(
                exporter,
                source: source,
                folder: folder,
                baseName: "low-\(format.rawValue)",
                options: ExportOptions(format: format, quality: 0.2)
            )
            let high = try await export(
                exporter,
                source: source,
                folder: folder,
                baseName: "high-\(format.rawValue)",
                options: ExportOptions(format: format, quality: 0.95)
            )

            #expect(high.byteCount > low.byteCount, "\(format.rawValue) ignored the quality")
        }
    }

    // MARK: - Metadata

    @Test("Metadata and the colour profile survive an export, and GPS can be stripped")
    func metadata() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try writeSource(
            in: folder,
            name: "source.jpg",
            width: 40,
            height: 24,
            colorSpace: CGColorSpace(name: CGColorSpace.displayP3),
            properties: metadataProperties
        )
        let exporter = PhotoExporter(renderer: editor)
        let expectedColorSpace = CGColorSpace(name: CGColorSpace.displayP3)?.name as String?

        for format in ExportFormat.allCases {
            let kept = try await export(
                exporter,
                source: source,
                folder: folder,
                baseName: "kept-\(format.rawValue)",
                options: ExportOptions(format: format, quality: 0.8, removeLocation: false)
            )
            let keptProperties = try properties(of: kept.url)

            #expect(
                (keptProperties[kCGImagePropertyOrientation] as? NSNumber)?.intValue == 1,
                "\(format.rawValue) kept the source orientation"
            )
            #expect((keptProperties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue == 24)
            #expect((keptProperties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue == 40)

            let exif = keptProperties[kCGImagePropertyExifDictionary] as? [CFString: Any]
            #expect(exif?[kCGImagePropertyExifLensModel] as? String == "Probe Lens")

            let gps = keptProperties[kCGImagePropertyGPSDictionary] as? [CFString: Any]
            #expect((gps?[kCGImagePropertyGPSLatitude] as? NSNumber)?.doubleValue == 48.8566)

            let keptSource = try #require(CGImageSourceCreateWithURL(kept.url as CFURL, nil))
            let keptImage = try #require(CGImageSourceCreateImageAtIndex(keptSource, 0, nil))
            #expect(
                keptImage.colorSpace?.name as String? == expectedColorSpace,
                "\(format.rawValue) lost the Display P3 profile"
            )

            let stripped = try await export(
                exporter,
                source: source,
                folder: folder,
                baseName: "stripped-\(format.rawValue)",
                options: ExportOptions(format: format, quality: 0.8, removeLocation: true)
            )
            let strippedProperties = try properties(of: stripped.url)
            #expect(
                strippedProperties[kCGImagePropertyGPSDictionary] == nil,
                "\(format.rawValue) kept the GPS dictionary"
            )
            #expect((strippedProperties[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifLensModel] as? String == "Probe Lens")
        }
    }

    // MARK: - Names and originals

    @Test("An export never overwrites the source, and a collision gets a counter")
    func collisionAndSourceProtection() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try writeSource(in: folder, name: "IMG_0001.jpg", width: 64, height: 48)
        let before = try Data(contentsOf: source)
        let exporter = PhotoExporter(renderer: editor)

        let first = try await export(
            exporter,
            source: source,
            folder: folder,
            baseName: "IMG_0001",
            options: ExportOptions(format: .jpeg)
        )
        #expect(first.url.lastPathComponent == "IMG_0001 2.jpg")

        let second = try await export(
            exporter,
            source: source,
            folder: folder,
            baseName: "IMG_0001",
            options: ExportOptions(format: .jpeg)
        )
        #expect(second.url.lastPathComponent == "IMG_0001 3.jpg")

        let after = try Data(contentsOf: source)
        #expect(after == before, "The original was modified")
    }

    // MARK: - Failures

    @Test("An unreadable source and a missing folder fail with useful errors")
    func failures() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let exporter = PhotoExporter(renderer: editor)

        let missingSource = folder.appending(path: "missing.png")
        await #expect(throws: PhotoExportError.unreadable) {
            try await exporter.export(
                PhotoExportRequest(
                    photo: item(missingSource),
                    recipe: .identity,
                    folder: folder,
                    baseName: "out",
                    options: ExportOptions(format: .png)
                )
            )
        }

        let source = try writeSource(in: folder, name: "source.png", width: 64, height: 48)
        let missingFolder = folder.appending(path: "missing-folder", directoryHint: .isDirectory)
        await #expect(throws: PhotoExportError.couldNotWrite) {
            try await exporter.export(
                PhotoExportRequest(
                    photo: item(source),
                    recipe: .identity,
                    folder: missingFolder,
                    baseName: "out",
                    options: ExportOptions(format: .png)
                )
            )
        }

        let contents = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        #expect(!contents.contains { $0.hasPrefix(".photon-") }, "A failed export left a temporary file")
    }

    @Test("Cancel stops the export and leaves nothing behind")
    func cancellation() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try writeSource(in: folder, name: "source.png", width: 64, height: 48)
        let exporter = PhotoExporter(renderer: StubPhotoEditor(delay: .milliseconds(100)))

        let task = Task {
            try await exporter.export(
                PhotoExportRequest(
                    photo: item(source),
                    recipe: .identity,
                    folder: folder,
                    baseName: "cancelled",
                    options: ExportOptions(format: .png)
                )
            )
        }

        try? await Task.sleep(for: .milliseconds(10))
        task.cancel()

        await #expect(throws: PhotoExportError.cancelled) {
            try await task.value
        }

        let contents = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        #expect(!contents.contains { $0.hasPrefix(".photon-") })
        #expect(!contents.contains("cancelled.png"))
    }

    // MARK: - Helpers

    private func export(
        _ exporter: PhotoExporter,
        source: URL,
        folder: URL,
        baseName: String,
        options: ExportOptions
    ) async throws -> ExportedPhoto {
        try await exporter.export(
            PhotoExportRequest(
                photo: item(source),
                recipe: .identity,
                folder: folder,
                baseName: baseName,
                options: options
            )
        )
    }

    private func item(_ url: URL) -> PhotoItem {
        PhotoItem(url: url, subfolderPath: "", isRAW: false)
    }

    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "PhotonExporterTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private var metadataProperties: [CFString: Any] {
        [
            kCGImagePropertyOrientation: 6,
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifLensModel: "Probe Lens"
            ] as [CFString: Any],
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 48.8566,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 2.3522,
                kCGImagePropertyGPSLongitudeRef: "E",
            ] as [CFString: Any],
        ]
    }

    private func properties(of url: URL) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    /// Writes a source image, optionally with a colour profile, an orientation
    /// and EXIF/GPS, so the export has something to preserve.
    private func writeSource(
        in folder: URL,
        name: String,
        width: Int,
        height: Int,
        colorSpace: CGColorSpace? = nil,
        properties: [CFString: Any] = [:],
        noise: Bool = false
    ) throws -> URL {
        let colorSpace = colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw FixtureError.couldNotMakeImage
        }

        if noise {
            for y in 0..<height {
                for x in 0..<width {
                    let red = CGFloat((x * 37 + y * 11) % 256) / 255
                    let green = CGFloat((x * 13 + y * 41) % 256) / 255
                    let blue = CGFloat((x * 7 + y * 3) % 256) / 255
                    context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
                    context.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        } else {
            context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.7, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }

        guard let image = context.makeImage() else { throw FixtureError.couldNotMakeImage }

        let url = folder.appending(path: name)
        let type = UTType(filenameExtension: url.pathExtension) ?? .png
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            type.identifier as CFString,
            1,
            nil
        ) else {
            throw FixtureError.couldNotWrite
        }

        var properties = properties
        if type == .jpeg {
            properties[kCGImageDestinationLossyCompressionQuality] = 0.9
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw FixtureError.couldNotWrite }
        return url
    }

    private enum FixtureError: Error {
        case couldNotMakeImage
        case couldNotWrite
    }
}

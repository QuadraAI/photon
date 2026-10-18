//
//  PhotoExporter.swift
//  Photon
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import os

/// ``PhotoExporting`` backed by the editing engine and ImageIO.
actor PhotoExporter: PhotoExporting {
    private let logger = Logger(subsystem: "com.quadra.Photon", category: "PhotoExporter")
    private let renderer: PhotoEditing

    init(renderer: PhotoEditing) {
        self.renderer = renderer
    }

    func export(_ request: PhotoExportRequest) async throws(PhotoExportError) -> ExportedPhoto {
        guard !Task.isCancelled else { throw .cancelled }

        // The default folder is covered by the open folder's scope; a picked
        // folder brings its own. A false answer here is not an error.
        let isScoped = request.folder.startAccessingSecurityScopedResource()
        defer {
            if isScoped { request.folder.stopAccessingSecurityScopedResource() }
        }

        let image: CGImage
        do {
            image = try await renderer.render(request.photo.url, recipe: request.recipe, maxPixelSize: nil)
        } catch {
            if Task.isCancelled { throw .cancelled }
            logger.error("Could not render \(request.photo.url.path(percentEncoded: false)) for export")
            throw .unreadable
        }

        guard !Task.isCancelled else { throw .cancelled }

        // ImageIO's AVIF writer creates a sandbox sidecar beside its output. A
        // user-selected folder is reachable by Photon but not by that sidecar
        // writer, so AVIF finalisation failed there. Encode in the container,
        // then copy the finished file in.
        let encoded = FileManager.default.temporaryDirectory.appending(
            path: ".photon-\(UUID().uuidString).\(request.options.format.fileExtension)"
        )
        defer { try? FileManager.default.removeItem(at: encoded) }

        guard let imageDestination = CGImageDestinationCreateWithURL(
            encoded as CFURL,
            request.options.format.utType.identifier as CFString,
            1,
            nil
        ) else {
            logger.error("Could not create \(request.options.format.rawValue) destination")
            throw .couldNotEncode
        }

        CGImageDestinationAddImage(
            imageDestination,
            image,
            destinationProperties(for: request, image: image) as CFDictionary
        )

        guard CGImageDestinationFinalize(imageDestination) else {
            logger.error("Could not encode \(request.photo.url.path(percentEncoded: false))")
            throw .couldNotEncode
        }

        guard !Task.isCancelled else { throw .cancelled }

        let destinationTemporary = request.folder.appending(
            path: ".photon-copy-\(UUID().uuidString).\(request.options.format.fileExtension)"
        )
        defer { try? FileManager.default.removeItem(at: destinationTemporary) }

        do {
            try FileManager.default.copyItem(at: encoded, to: destinationTemporary)
        } catch {
            logger.error("Could not copy the export into \(request.folder.path(percentEncoded: false))")
            throw .couldNotWrite
        }

        guard let destination = ExportFilename.destinationURL(
            in: request.folder,
            baseName: request.baseName,
            format: request.options.format,
            sourceURL: request.photo.url
        ) else {
            logger.error("The export name normalised to nothing")
            throw .couldNotEncode
        }

        do {
            try FileManager.default.moveItem(at: destinationTemporary, to: destination)
        } catch {
            logger.error("Could not move the export into \(request.folder.path(percentEncoded: false))")
            throw .couldNotWrite
        }

        let byteCount = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ExportedPhoto(
            url: destination,
            pixelSize: CGSize(width: image.width, height: image.height),
            byteCount: byteCount
        )
    }

    // MARK: - Metadata

    /// Copies the source metadata, with the parts that must follow the new
    /// pixels corrected: orientation is upright now, and the dimensions are the
    /// output's. EXIF, TIFF, IPTC and GPS are copied; the ICC profile travels
    /// with the image's colour space, and XMP is not copied.
    private func destinationProperties(for request: PhotoExportRequest, image: CGImage) -> [CFString: Any] {
        var properties: [CFString: Any] = [
            kCGImagePropertyOrientation: 1,
            kCGImagePropertyPixelWidth: image.width,
            kCGImagePropertyPixelHeight: image.height,
        ]

        if let source = CGImageSourceCreateWithURL(
            request.photo.url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ), let sourceProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            if var exif = dictionary(sourceProperties[kCGImagePropertyExifDictionary]) {
                exif[kCGImagePropertyExifPixelXDimension] = image.width
                exif[kCGImagePropertyExifPixelYDimension] = image.height
                properties[kCGImagePropertyExifDictionary] = exif
            }

            if var tiff = dictionary(sourceProperties[kCGImagePropertyTIFFDictionary]) {
                tiff[kCGImagePropertyTIFFOrientation] = 1
                properties[kCGImagePropertyTIFFDictionary] = tiff
            }

            if let iptc = dictionary(sourceProperties[kCGImagePropertyIPTCDictionary]) {
                properties[kCGImagePropertyIPTCDictionary] = iptc
            }

            if !request.options.removeLocation,
               let gps = dictionary(sourceProperties[kCGImagePropertyGPSDictionary]) {
                properties[kCGImagePropertyGPSDictionary] = gps
            }
        }

        if request.options.format.isLossy {
            properties[kCGImageDestinationLossyCompressionQuality] = request.options.quality
        }

        return properties
    }

    /// Reads a nested metadata dictionary, whichever bridge ImageIO used.
    private func dictionary(_ value: Any?) -> [CFString: Any]? {
        if let dictionary = value as? [CFString: Any] { return dictionary }
        guard let dictionary = value as? [String: Any] else { return nil }
        return Dictionary(uniqueKeysWithValues: dictionary.map { ($0.key as CFString, $0.value) })
    }
}

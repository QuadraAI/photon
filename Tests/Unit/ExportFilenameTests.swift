//
//  ExportFilenameTests.swift
//  PhotonTests
//

import Foundation
import Testing

@testable import Photon

@Suite("Export filenames")
struct ExportFilenameTests {
    @Test("The default name is the photo's own with -edit")
    func defaultName() {
        let photo = PhotoItem.fixture(name: "IMG_0001.HEIC")

        #expect(ExportFilename.defaultBaseName(for: photo) == "IMG_0001-edit")
    }

    @Test("Path separators and the Finder's colon become hyphens")
    func separators() {
        #expect(ExportFilename.normalizedBaseName("a/b:c") == "a-b-c")
        #expect(ExportFilename.normalizedBaseName("a\nb") == "a-b")
    }

    @Test("A name is not a hidden file or a trail of dots")
    func dots() {
        #expect(ExportFilename.normalizedBaseName(".hidden") == "hidden")
        #expect(ExportFilename.normalizedBaseName("photo...") == "photo")
        #expect(ExportFilename.normalizedBaseName("...") == "")
    }

    @Test("A pasted image extension is replaced by the selected format's")
    func pastedExtension() {
        #expect(ExportFilename.fileName(baseName: "photo.jpg", format: .avif) == "photo.avif")
        #expect(ExportFilename.fileName(baseName: "photo.JPEG", format: .png) == "photo.png")
        #expect(ExportFilename.fileName(baseName: "photo.tif", format: .tiff) == "photo.tiff")
    }

    @Test("A dot that is not an image extension belongs to the name")
    func ordinaryDot() {
        #expect(ExportFilename.fileName(baseName: "shot.v2", format: .jpeg) == "shot.v2.jpg")
    }

    @Test("A name with nothing left has no file name")
    func emptyName() {
        #expect(ExportFilename.fileName(baseName: "", format: .jpeg) == nil)
        #expect(ExportFilename.fileName(baseName: "  ...  ", format: .jpeg) == nil)
    }

    @Test("A collision gets the next free counter")
    func collision() {
        let folder = URL(filePath: "/tmp/Photos", directoryHint: .isDirectory)
        let taken: Set<String> = [
            "/tmp/Photos/IMG-edit.jpg",
            "/tmp/Photos/IMG-edit 2.jpg",
        ]

        let destination = ExportFilename.destinationURL(
            in: folder,
            baseName: "IMG-edit",
            format: .jpeg,
            sourceURL: nil
        ) { taken.contains($0.path) }

        #expect(destination?.lastPathComponent == "IMG-edit 3.jpg")
    }

    @Test("The source photo's own URL is never offered as the destination")
    func sourceProtection() {
        let folder = URL(filePath: "/tmp/Photos", directoryHint: .isDirectory)
        let source = folder.appending(path: "IMG.jpg")

        let destination = ExportFilename.destinationURL(
            in: folder,
            baseName: "IMG",
            format: .jpeg,
            sourceURL: source
        ) { $0 == source }

        #expect(destination?.lastPathComponent == "IMG 2.jpg")
    }

    @Test("The source comparison ignores case, as the usual volume does")
    func sourceCaseInsensitive() {
        let folder = URL(filePath: "/tmp/Photos", directoryHint: .isDirectory)
        let source = folder.appending(path: "IMG.JPG")

        let destination = ExportFilename.destinationURL(
            in: folder,
            baseName: "IMG",
            format: .jpeg,
            sourceURL: source
        ) { $0.path.caseInsensitiveCompare(source.path) == .orderedSame }

        #expect(destination?.lastPathComponent == "IMG 2.jpg")
    }

    @Test("A very long name is capped before the extension")
    func longName() {
        let name = String(repeating: "a", count: 300)
        let fileName = ExportFilename.fileName(baseName: name, format: .png)

        #expect(fileName?.count == 204)
        #expect(fileName?.hasSuffix(".png") == true)
    }
}

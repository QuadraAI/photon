//
//  FileSystemPhotoLibraryTests.swift
//  PhotonTests
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import Photon

/// Exercises the real directory walk against a real tree of real image files.
///
/// An integration test rather than a unit test: what matters here is what
/// `FileManager` and `UTType` actually do with files on disk, which a stub would
/// only pretend to know.
@Suite("File system photo library")
struct FileSystemPhotoLibraryTests {
    @Test("Finds images in the folder and in its subfolders")
    func findsNestedImages() async throws {
        let tree = try PhotoTree()
        defer { tree.remove() }
        try tree.addImage("alpha.png")
        try tree.addImage("nested/gamma.png")

        let photos = try await FileSystemPhotoLibrary().photos(in: tree.root)

        #expect(photos.map(\.name) == ["alpha.png", "gamma.png"])
    }

    @Test("Ignores files that are not images")
    func ignoresNonImages() async throws {
        let tree = try PhotoTree()
        defer { tree.remove() }
        try tree.addImage("alpha.png")
        try tree.addText("notes.txt")

        let photos = try await FileSystemPhotoLibrary().photos(in: tree.root)

        #expect(photos.map(\.name) == ["alpha.png"])
    }

    @Test("Ignores hidden files")
    func ignoresHiddenFiles() async throws {
        let tree = try PhotoTree()
        defer { tree.remove() }
        try tree.addImage("alpha.png")
        try tree.addImage(".hidden.png")

        let photos = try await FileSystemPhotoLibrary().photos(in: tree.root)

        #expect(photos.map(\.name) == ["alpha.png"])
    }

    @Test("Does not descend into packages")
    func skipsPackages() async throws {
        let tree = try PhotoTree()
        defer { tree.remove() }
        try tree.addImage("alpha.png")
        // A photo library or an app bundle is a single item to the user, not a
        // folder full of editable pictures.
        try tree.addImage("Library.photoslibrary/originals/inside.png")

        let photos = try await FileSystemPhotoLibrary().photos(in: tree.root)

        #expect(photos.map(\.name) == ["alpha.png"])
    }

    @Test("Sorts by name the way a person reads it")
    func sortsNaturally() async throws {
        let tree = try PhotoTree()
        defer { tree.remove() }
        for name in ["IMG_10.png", "IMG_2.png", "IMG_1.png"] {
            try tree.addImage(name)
        }

        let photos = try await FileSystemPhotoLibrary().photos(in: tree.root)

        #expect(photos.map(\.name) == ["IMG_1.png", "IMG_2.png", "IMG_10.png"])
    }

    @Test("Records the subfolder each photo came from")
    func reportsSubfolderPath() async throws {
        let tree = try PhotoTree()
        defer { tree.remove() }
        try tree.addImage("alpha.png")
        try tree.addImage("Holiday/Sub/gamma.png")

        let photos = try await FileSystemPhotoLibrary().photos(in: tree.root)

        let byName = Dictionary(uniqueKeysWithValues: photos.map { ($0.name, $0.subfolderPath) })
        #expect(byName["alpha.png"] == "")
        #expect(byName["gamma.png"] == "Holiday/Sub")
    }

    @Test("A folder that does not exist is reported as unreadable")
    func missingFolderIsUnreadable() async throws {
        let missing = FileManager.default.temporaryDirectory
            .appending(path: "PhotonMissing-\(UUID().uuidString)")

        await #expect(throws: PhotoLibraryError.unreadable) {
            try await FileSystemPhotoLibrary().photos(in: missing)
        }
    }

    @Test("An empty folder is not a failure")
    func emptyFolderSucceeds() async throws {
        let tree = try PhotoTree()
        defer { tree.remove() }

        let photos = try await FileSystemPhotoLibrary().photos(in: tree.root)

        #expect(photos.isEmpty)
    }

    @Test("Stops at the cap instead of walking an entire disk")
    func stopsAtTheCap() async throws {
        let tree = try PhotoTree()
        defer { tree.remove() }
        for index in 0..<6 {
            try tree.addImage("photo-\(index).png")
        }

        let photos = try await FileSystemPhotoLibrary(maximumPhotoCount: 3).photos(in: tree.root)

        #expect(photos.count == 3)
    }
}

/// A throwaway folder of real image files.
private struct PhotoTree {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "PhotonPhotoTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// Writes a real, decodable PNG at `path`, creating intermediate folders.
    func addImage(_ path: String) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let destination = try #require(
            CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, try #require(Self.pixel()), nil)
        try #require(CGImageDestinationFinalize(destination))
    }

    func addText(_ path: String) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not a photo".utf8).write(to: url)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    /// A 1×1 image, which is all the scanner should care about.
    private static func pixel() -> CGImage? {
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

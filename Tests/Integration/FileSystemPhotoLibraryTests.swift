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

    @Test("Photos sharing a name are ordered by the folder they came from")
    func sortsByFolderWhenNamesMatch() async throws {
        let tree = try PhotoTree()
        defer { tree.remove() }
        try tree.addImage("Zulu/IMG_1.png")
        try tree.addImage("Alpha/IMG_1.png")
        try tree.addImage("IMG_1.png")

        let photos = try await FileSystemPhotoLibrary().photos(in: tree.root)

        // The name leads, so the three stay together; the folder decides the tie.
        #expect(photos.map(\.subfolderPath) == ["", "Alpha", "Zulu"])
    }

    @Test("A camera raw file is marked for the raw pipeline")
    func marksRawFiles() async throws {
        let tree = try PhotoTree()
        defer { tree.remove() }
        try tree.addImage("shot.png")
        // The type comes off the name; nothing decodes this.
        try tree.addText("shot.nef")

        let photos = try await FileSystemPhotoLibrary().photos(in: tree.root)

        let byName = Dictionary(uniqueKeysWithValues: photos.map { ($0.name, $0.isRAW) })
        #expect(byName["shot.png"] == false)
        #expect(byName["shot.nef"] == true)
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

    // MARK: - Benchmark

    /// Opt-in, because it writes five thousand files:
    ///
    ///     PHOTON_BENCHMARK=1 xcodebuild test -only-testing:PhotonTests/FileSystemPhotoLibraryTests
    ///
    /// It reports timings rather than asserting them.
    @Test(
        "Reports what a five-thousand-photo tree costs to scan and to filter",
        .enabled(if: ProcessInfo.processInfo.environment["PHOTON_BENCHMARK"] != nil)
    )
    @MainActor
    func benchmarkLargeTree() async throws {
        let tree = try PhotoTree()
        defer { tree.remove() }
        for folder in 0..<200 {
            for photo in 0..<25 {
                try tree.addImage("Trip-\(folder % 37)/Album \(folder)/IMG_\(1_000 + photo).png")
            }
        }

        let library = FileSystemPhotoLibrary()
        let clock = ContinuousClock()
        let scanStart = clock.now
        #expect(try await library.photos(in: tree.root).count == 5_000)
        let scan = scanStart.duration(to: clock.now)

        let editor = EditorViewModel(library: library, renderer: StubPhotoRenderer())
        await editor.load(AuthorizedFolder(url: tree.root, bookmark: nil))
        let filterStart = clock.now
        editor.filter = "IMG_10"
        let filter = filterStart.duration(to: clock.now)

        print("Photon benchmark — 5,000 photos, 200 subfolders: scan \(scan), filter \(filter), matched \(editor.matches.count)")
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

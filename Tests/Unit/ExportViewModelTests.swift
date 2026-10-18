//
//  ExportViewModelTests.swift
//  PhotonTests
//

import CoreGraphics
import Foundation
import Testing

@testable import Photon

@Suite("Export view model")
@MainActor
struct ExportViewModelTests {
    @Test("The sheet starts from the remembered choices and the photo's own folder")
    func defaults() {
        let (app, _) = makeApp(format: .png, quality: 0.55)
        let model = makeModel(preferences: app)

        #expect(model.format == .png)
        #expect(model.quality == 0.55)
        #expect(model.baseName == "IMG_0001-edit")
        #expect(model.folder.path == "/tmp/Photos")
        #expect(model.phase == .editing)
        #expect(!model.removeLocation)
        #expect(!model.hasUnappliedCrop)
    }

    @Test("A stored quality outside the range is clamped")
    func qualityIsClamped() {
        let (app, _) = makeApp(quality: 4)
        let model = makeModel(preferences: app)

        #expect(model.quality == 1)
    }

    @Test("The output dimensions follow the committed crop and turn")
    func outputDimensions() {
        let half = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let straight = makeModel(recipe: EditRecipe(crop: Crop(rect: half, aspect: .free, rotation: .none)))
        #expect(straight.outputWidth == 2000)
        #expect(straight.outputHeight == 1500)

        let turned = makeModel(recipe: EditRecipe(crop: Crop(rect: half, aspect: .free, rotation: .clockwise)))
        #expect(turned.outputWidth == 1500)
        #expect(turned.outputHeight == 2000)
    }

    @Test("A name with nothing left cannot be exported")
    func invalidName() {
        let model = makeModel()
        #expect(model.canExport)

        model.baseName = "  ...  "
        #expect(model.fileName == nil)
        #expect(!model.canExport)
    }

    @Test("A successful export asks for the chosen options and lands in the success state")
    func successfulExport() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let photo = PhotoItem(url: folder.appending(path: "IMG_0001.heic"), subfolderPath: "", isRAW: false)
        let exporter = StubPhotoExporter(
            pixelSize: CGSize(width: 1200, height: 800),
            byteCount: 4_321
        )
        let (app, _) = makeApp()
        let model = makeModel(exporter: exporter, preferences: app, photo: photo)
        model.format = .png
        model.baseName = "out"
        model.quality = 0.4
        model.removeLocation = true

        model.export()
        await waitForExport(model)

        #expect(exporter.requested.count == 1)
        let request = try #require(exporter.requested.first)
        #expect(request.photo == photo)
        #expect(request.folder.path == folder.path)
        #expect(request.baseName == "out")
        #expect(request.options.format == .png)
        #expect(request.options.quality == 0.4)
        #expect(request.options.removeLocation)
        #expect(request.recipe == .identity)

        let exported = try #require(model.exportedPhoto)
        #expect(model.phase == .succeeded(exported))
        #expect(exported.url.lastPathComponent == "out.png")
        #expect(exported.pixelSize == CGSize(width: 1200, height: 800))
        #expect(exported.byteCount == 4_321)
        #expect(!model.canExport)
    }

    @Test("A failed export stays retryable")
    func failedExport() async {
        let exporter = StubPhotoExporter(failure: .couldNotWrite)
        let model = makeModel(exporter: exporter)

        model.export()
        await waitForExport(model)

        #expect(model.failure == .couldNotWrite)
        #expect(model.phase == .failed(.couldNotWrite))
        #expect(model.canExport)
    }

    @Test("Cancel stops the write and puts the form back")
    func cancel() async {
        let exporter = StubPhotoExporter(delay: .milliseconds(50))
        let model = makeModel(exporter: exporter)

        model.export()
        #expect(model.isExporting)

        model.cancel()
        #expect(model.phase == .editing)

        try? await Task.sleep(for: .milliseconds(100))
        #expect(model.phase == .editing)
        #expect(model.exportedPhoto == nil)
    }

    @Test("Closing remembers the chosen format and quality once")
    func closePersistsDefaults() {
        let (app, store) = makeApp(format: .jpeg, quality: 0.85)
        let model = makeModel(preferences: app)
        model.format = .png
        model.quality = 0.5
        let writes = store.saves

        model.close()

        #expect(store.stored.exportFormat == .png)
        #expect(store.stored.exportQuality == 0.5)
        #expect(store.saves == writes + 1)

        model.close()
        #expect(store.saves == writes + 1, "A second close is a no-op")
    }

    @Test("A chosen folder replaces the photo's own")
    func chooseFolder() throws {
        let first = try makeFolder()
        defer { try? FileManager.default.removeItem(at: first) }
        let second = try makeFolder()
        defer { try? FileManager.default.removeItem(at: second) }

        let photo = PhotoItem(url: first.appending(path: "IMG_0001.heic"), subfolderPath: "", isRAW: false)
        let model = makeModel(photo: photo)
        #expect(model.folder.path == first.path)

        model.setFolder(second)
        #expect(model.folder.path == second.path)
    }

    @Test("An unapplied crop is carried for the sheet to explain")
    func unappliedCrop() {
        let model = makeModel(hasUnappliedCrop: true)
        #expect(model.hasUnappliedCrop)
    }

    // MARK: - Helpers

    private func makeApp(
        format: ExportFormat = .jpeg,
        quality: Double = 0.85
    ) -> (AppViewModel, InMemoryPreferencesStore) {
        let store = InMemoryPreferencesStore(
            initial: AppPreferences(exportFormat: format, exportQuality: quality)
        )
        return (makeAppViewModel(preferences: store), store)
    }

    private func makeModel(
        exporter: StubPhotoExporter = StubPhotoExporter(),
        preferences: AppViewModel? = nil,
        photo: PhotoItem = .fixture(),
        recipe: EditRecipe = .identity,
        sourceSize: CGSize = CGSize(width: 4000, height: 3000),
        hasUnappliedCrop: Bool = false
    ) -> ExportViewModel {
        ExportViewModel(
            photo: photo,
            recipe: recipe,
            sourceSize: sourceSize,
            hasUnappliedCrop: hasUnappliedCrop,
            exporter: exporter,
            preferences: preferences ?? makeAppViewModel()
        )
    }

    private func waitForExport(_ model: ExportViewModel) async {
        var remaining = 200
        while model.isExporting, remaining > 0 {
            try? await Task.sleep(for: .milliseconds(5))
            remaining -= 1
        }
    }

    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "PhotonExportModelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}

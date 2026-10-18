//
//  ExportViewModel.swift
//  Photon
//

import CoreGraphics
import Foundation
import Observation

/// One photo's export, owned by the window that opened the sheet.
///
/// Snapshots the photo, the committed recipe and its size when it is made, so a
/// selection change or a tool still open behind the sheet cannot change what is
/// being exported.
@Observable
@MainActor
final class ExportViewModel: Identifiable {
    enum Phase: Equatable {
        case editing
        case exporting
        case succeeded(ExportedPhoto)
        case failed(PhotoExportError)
    }

    let id = UUID()
    let photo: PhotoItem
    let recipe: EditRecipe
    let sourceSize: CGSize

    /// Whether the crop tool holds a draft that is not part of this export.
    let hasUnappliedCrop: Bool

    var format: ExportFormat
    var baseName: String
    var quality: Double
    var removeLocation = false

    private(set) var folder: URL
    private(set) var phase: Phase = .editing

    private let exporter: PhotoExporting
    private let preferences: AppViewModel

    @ObservationIgnored private var task: Task<Void, Never>?

    /// Held while the sheet is open so the exporter and Open can reach the folder.
    @ObservationIgnored private var scopedFolder: URL?

    init(
        photo: PhotoItem,
        recipe: EditRecipe,
        sourceSize: CGSize,
        hasUnappliedCrop: Bool,
        exporter: PhotoExporting,
        preferences: AppViewModel
    ) {
        self.photo = photo
        self.recipe = recipe
        self.sourceSize = sourceSize
        self.hasUnappliedCrop = hasUnappliedCrop
        self.exporter = exporter
        self.preferences = preferences

        format = preferences.preferences.exportFormat
        baseName = ExportFilename.defaultBaseName(for: photo)
        quality = preferences.preferences.exportQuality.clamped(to: ExportOptions.qualityRange)
        folder = photo.url.deletingLastPathComponent()
        holdFolderScope()
    }

    // MARK: - Reading

    /// The complete name the file would get, or nil when the field is empty.
    var fileName: String? {
        ExportFilename.fileName(baseName: baseName, format: format)
    }

    var folderName: String { folder.lastPathComponent }

    var isExporting: Bool { phase == .exporting }

    var exportedPhoto: ExportedPhoto? {
        if case .succeeded(let photo) = phase { return photo }
        return nil
    }

    var failure: PhotoExportError? {
        if case .failed(let error) = phase { return error }
        return nil
    }

    var canExport: Bool {
        switch phase {
        case .editing, .failed: fileName != nil
        case .exporting, .succeeded: false
        }
    }

    var outputWidth: Int { Int(outputSize.width.rounded()) }
    var outputHeight: Int { Int(outputSize.height.rounded()) }

    private var outputSize: CGSize {
        guard sourceSize.width > 0, sourceSize.height > 0 else { return .zero }
        let frame = CropGeometry.turnedSize(sourceSize, by: recipe.crop.rotation)
        return CropGeometry.pixelRect(recipe.crop.rect, in: frame).size
    }

    // MARK: - Actions

    /// Points the export at a folder the system picker handed over.
    func setFolder(_ url: URL) {
        guard url != folder else { return }
        releaseFolderScope()
        folder = url
        holdFolderScope()
    }

    /// Renders and writes the photo, and moves the sheet into its result state.
    func export() {
        guard canExport else { return }

        preferences.setExportDefaults(format: format, quality: quality)

        let request = PhotoExportRequest(
            photo: photo,
            recipe: recipe,
            folder: folder,
            baseName: baseName,
            options: ExportOptions(format: format, quality: quality, removeLocation: removeLocation)
        )

        phase = .exporting
        task = Task { [exporter] in
            do {
                let result = try await exporter.export(request)
                guard !Task.isCancelled else { return }
                phase = .succeeded(result)
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed((error as? PhotoExportError) ?? .couldNotEncode)
            }
        }
    }

    /// Stops the write and puts the form back, without dismissing the sheet.
    func cancel() {
        guard isExporting else { return }
        task?.cancel()
        task = nil
        phase = .editing
    }

    /// Cancels anything outstanding and remembers the chosen format and quality.
    func close() {
        task?.cancel()
        task = nil
        releaseFolderScope()
        preferences.setExportDefaults(format: format, quality: quality)
    }

    // MARK: - Folder access

    /// Holds the picked folder's security scope while the sheet is open.
    ///
    /// The default folder is already covered by the open folder's scope, in
    /// which case this returns false and there is nothing to release.
    private func holdFolderScope() {
        if folder.startAccessingSecurityScopedResource() {
            scopedFolder = folder
        }
    }

    private func releaseFolderScope() {
        scopedFolder?.stopAccessingSecurityScopedResource()
        scopedFolder = nil
    }
}

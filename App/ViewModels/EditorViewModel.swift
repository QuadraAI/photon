//
//  EditorViewModel.swift
//  Photon
//

import CoreGraphics
import Foundation
import Observation
import os

/// Window-scoped view model: the folder's photos, which one is on the canvas,
/// and which tool panel is open.
///
/// Owned by ``RootView`` with `@State` alongside ``FolderViewModel``, so each
/// window browses independently.
@Observable
@MainActor
final class EditorViewModel {
    /// What the media sidebar is showing.
    enum Library: Equatable {
        case loading
        /// Every photo found, possibly none — an empty folder is a normal state,
        /// not a failure, so it does not get its own case.
        case loaded([PhotoItem])
        case failed(PhotoLibraryError)
    }

    /// What the canvas is showing.
    ///
    /// One enum rather than an item plus a separate image, because those two
    /// could disagree. Deliberately not `Equatable`: `CGImage` is a reference
    /// type, and tests match on the case rather than compare payloads.
    enum Canvas {
        case nothingSelected
        case loading(PhotoItem)
        case ready(PhotoItem, CGImage)
        case failed(PhotoItem)
    }

    /// What the media sidebar is showing; ``visiblePhotos`` is derived from it.
    private(set) var library: Library = .loading {
        didSet { refreshVisiblePhotos() }
    }

    private(set) var canvas: Canvas = .nothingSelected
    private(set) var selection: PhotoItem?

    /// Which tool's panel is open. `nil` is the resting state, where the rail
    /// shows icons only.
    private(set) var openTool: Tool?

    var isSidebarVisible = true

    /// How wide the tool panel is, in points, for this window only.
    ///
    /// The sidebar's width is the split view's; only the panel is still a pane we
    /// place ourselves.
    private(set) var panelWidth = AppLayout.toolPanelWidth

    private(set) var canUndo = false
    private(set) var canRedo = false

    /// Guards the macOS window maximiser so it runs once per window instead of
    /// fighting a user who resizes afterwards.
    private(set) var hasMaximizedWindow = false

    private let logger = Logger(subsystem: "com.quadra.Photon", category: "EditorViewModel")
    private let app: AppViewModel
    private let libraryLoader: PhotoLibraryLoading
    private let renderer: PhotoRendering

    /// The folder currently loaded, so ``retry()`` knows what to re-scan.
    @ObservationIgnored private var folder: AuthorizedFolder?

    /// The in-flight decode, cancelled when the selection moves on.
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    /// `UndoManager` is not observable, so its state is mirrored into
    /// ``canUndo``/``canRedo`` for the toolbar to react to.
    @ObservationIgnored private let undoManager = UndoManager()

    init(app: AppViewModel, library: PhotoLibraryLoading, renderer: PhotoRendering) {
        self.app = app
        self.libraryLoader = library
        self.renderer = renderer
    }

    // MARK: - Loading a folder

    /// Lists `folder`'s photos and clears everything that belonged to the last
    /// one.
    ///
    /// Returns immediately when `folder` is already the one on show, so a view
    /// that re-appears does not rescan the disk or reset state underneath a
    /// caller that has already moved on.
    func load(_ folder: AuthorizedFolder) async {
        guard self.folder?.url != folder.url else { return }
        await scan(folder)
    }

    /// Re-scans the current folder after a failure.
    func retry() async {
        guard let folder else { return }
        await scan(folder)
    }

    private func scan(_ folder: AuthorizedFolder) async {
        self.folder = folder
        loadTask?.cancel()
        selection = nil
        canvas = .nothingSelected
        openTool = nil
        library = .loading
        // Both assignments empty the sidebar through the observers above, and a
        // filter belongs to the list it was typed against.
        filter = ""
        clearUndoHistory()

        do {
            let photos = try await libraryLoader.photos(in: folder.url)
            // A newer folder may have been requested, and a cancelled walk
            // reports no photos at all.
            guard self.folder?.url == folder.url, !Task.isCancelled else { return }
            library = .loaded(photos)
        } catch {
            guard self.folder?.url == folder.url, !Task.isCancelled else { return }
            library = .failed(error)
        }
    }

    // MARK: - Selecting a photo

    /// Puts `item` on the canvas.
    ///
    /// Sets the selection straight away so a click highlights the row on the
    /// same frame, then decodes off the main actor.
    func beginSelecting(_ item: PhotoItem) {
        loadTask?.cancel()
        selection = item
        canvas = .loading(item)
        // Undo belongs to the photo it was recorded against; carrying it across
        // a selection change would let ⌘Z revert an edit the user cannot see.
        clearUndoHistory()

        loadTask = Task { [renderer] in
            do {
                let image = try await renderer.preview(for: item.url, maxPixelSize: AppLayout.previewMaxPixelSize)
                guard !Task.isCancelled else { return }
                canvas = .ready(item, image)
            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Could not display \(item.name): \(String(describing: error))")
                canvas = .failed(item)
            }
        }
    }

    /// ``beginSelecting(_:)``, then waits for the decode.
    ///
    /// The waiting is only useful to a caller that needs the photo on screen
    /// before carrying on, which in practice means tests.
    func select(_ item: PhotoItem) async {
        beginSelecting(item)
        await loadTask?.value
    }

    // MARK: - Filtering

    /// What the sidebar's filter field contains. Empty shows everything.
    var filter = "" {
        didSet { refreshVisiblePhotos() }
    }

    /// The photos the sidebar should list, in order.
    ///
    /// Stored: the sidebar reads it three times per body, so computing it would
    /// re-match every photo three times per keystroke.
    private(set) var visiblePhotos: [PhotoItem] = []

    /// True when a filter is hiding every photo, which is worth saying out loud
    /// rather than showing an empty list.
    var isFilteringToNothing: Bool {
        !filter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && visiblePhotos.isEmpty
    }

    /// Re-derives ``visiblePhotos``; `localizedStandardContains` so the match
    /// follows the system's case- and diacritic-insensitive rules.
    private func refreshVisiblePhotos() {
        guard case .loaded(let photos) = library else {
            visiblePhotos = []
            return
        }

        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        visiblePhotos = query.isEmpty ? photos : photos.filter { $0.name.localizedStandardContains(query) }
    }

    // MARK: - Tools

    /// Opens `tool`'s panel, swaps to it, or closes it when it is already open.
    func toggleTool(_ tool: Tool) {
        openTool = openTool == tool ? nil : tool
    }

    /// Clamped here, so a drag that runs off the end of the range is absorbed
    /// rather than banked.
    func setPanelWidth(_ width: CGFloat) {
        panelWidth = width.clamped(to: AppLayout.toolPanelWidthRange)
    }

    // MARK: - Undo

    /// Records one undoable step on the selected photo.
    ///
    /// Tools call this; nothing does yet, so ``canUndo`` and ``canRedo`` stay
    /// false and the toolbar's buttons stay disabled. The handler is `@MainActor`
    /// in the SDK, which is what lets `revert` touch UI state directly.
    func registerEdit(
        apply: @escaping @MainActor () -> Void,
        revert: @escaping @MainActor () -> Void
    ) {
        register(inverse: revert, forward: apply)
    }

    /// Registers the step that undoing runs, and the one that redoing runs.
    ///
    /// The two are swapped each time round: `UndoManager` redirects whatever is
    /// registered *during* an undo onto its redo stack, so re-registering the
    /// opposite closure is what makes one step undo and redo indefinitely. Using
    /// a single closure for both would re-run the revert on redo.
    private func register(
        inverse: @escaping @MainActor () -> Void,
        forward: @escaping @MainActor () -> Void
    ) {
        undoManager.registerUndo(withTarget: self) { editor in
            inverse()
            editor.register(inverse: forward, forward: inverse)
        }
        refreshUndoState()
    }

    func undo() {
        undoManager.undo()
        refreshUndoState()
    }

    func redo() {
        undoManager.redo()
        refreshUndoState()
    }

    // MARK: - Window

    func markWindowMaximized() {
        hasMaximizedWindow = true
    }

    // MARK: - Internals

    private func clearUndoHistory() {
        undoManager.removeAllActions()
        refreshUndoState()
    }

    private func refreshUndoState() {
        canUndo = undoManager.canUndo
        canRedo = undoManager.canRedo
    }
}

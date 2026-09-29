//
//  EditorViewModel.swift
//  Photon
//

import CoreGraphics
import Foundation
import Observation
import os

/// One row of the media sidebar's list: a folder, or a photo.
///
/// A tree, because a `List` lays out every row it is handed: folded up, a folder
/// of thousands costs one row.
nonisolated enum LibraryNode: Identifiable, Equatable {
    case folder(Folder)
    case photo(PhotoItem)

    /// A folder of the scanned root and what is directly inside it.
    nonisolated struct Folder: Identifiable, Equatable {
        /// Path relative to the scanned root, empty for the root itself.
        let path: String

        /// Photos and folders directly inside it, folders first.
        let children: [LibraryNode]

        /// How many photos are in it and everything below it.
        let photoCount: Int

        /// The folder's own URL, which is what its row is selected by.
        let id: URL

        /// The folder's own name, which is what its row reads.
        var name: String {
            String(path.split(separator: "/").last ?? "")
        }
    }

    var id: URL {
        switch self {
        case .folder(let folder): folder.id
        case .photo(let photo): photo.url
        }
    }

    /// The name its row reads, folder or photo.
    var name: String {
        switch self {
        case .folder(let folder): folder.name
        case .photo(let photo): photo.name
        }
    }
}

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

    /// What the media sidebar is showing; ``matches`` is derived from it.
    private(set) var library: Library = .loading

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
    private let libraryLoader: PhotoLibraryLoading
    private let renderer: PhotoRendering

    /// The folder currently loaded, so ``retry()`` knows what to re-scan.
    @ObservationIgnored private var folder: AuthorizedFolder?

    /// The in-flight decode, cancelled when the selection moves on.
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    /// `UndoManager` is not observable, so its state is mirrored into
    /// ``canUndo``/``canRedo`` for the toolbar to react to.
    @ObservationIgnored private let undoManager = UndoManager()

    init(library: PhotoLibraryLoading, renderer: PhotoRendering) {
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
        // A filter belongs to the list it was typed against, and the window
        // starts over with it. Assigning it is also what re-derives the list.
        library = .loading
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

        refreshMatches()
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
            // What the file already carries, so the canvas has the picture on it
            // in about a millisecond instead of after a full decode — 700 ms for
            // one of a Sony's raw files.
            if let draft = try? await renderer.draft(for: item.url, maxPixelSize: AppLayout.previewMaxPixelSize) {
                guard !Task.isCancelled else { return }
                canvas = .ready(item, draft)
            }

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
        didSet { refreshMatches() }
    }

    /// How many photos the folder holds, filter or no filter.
    ///
    /// What the sidebar shows its filter field from: a filter that hides
    /// everything must not take away the field that clears it.
    var foundCount: Int {
        if case .loaded(let photos) = library { return photos.count }
        return 0
    }

    /// The photos the filter lets through, in order.
    private(set) var matches: [PhotoItem] = []

    /// ``matches`` as the sidebar lists them: folders first, each holding its own
    /// photos and folders.
    private(set) var nodes: [LibraryNode] = []

    /// True when a filter is hiding every photo, which is worth saying out loud
    /// rather than showing an empty list.
    var isFilteringToNothing: Bool {
        !filter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && matches.isEmpty
    }

    /// Re-derives ``matches`` from ``library`` and ``filter``.
    ///
    /// `localizedStandardContains` so the match follows the system's case- and
    /// diacritic-insensitive rules.
    private func refreshMatches() {
        let photos: [PhotoItem]
        switch library {
        case .loaded(let loaded): photos = loaded
        case .loading, .failed: photos = []
        }

        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        matches = query.isEmpty ? photos : photos.filter { $0.name.localizedStandardContains(query) }
        nodes = Self.tree(of: matches, under: folder?.url)
    }

    /// The photo a row stands for, or nil for a folder's row.
    func photo(withNodeID id: URL) -> PhotoItem? {
        matches.first { $0.id == id }
    }

    /// Builds the tree the sidebar lists: folders first, then the folder's own
    /// photos, so one reads as a heading over its pictures. A folder that only
    /// holds other folders, as a camera's `100MSDCF` dumps do, is just those.
    private static func tree(of photos: [PhotoItem], under root: URL?) -> [LibraryNode] {
        guard let root else { return photos.map(LibraryNode.photo) }

        var byFolder: [String: [PhotoItem]] = [:]
        for photo in photos {
            byFolder[photo.subfolderPath, default: []].append(photo)
        }

        // Every folder on the way down to a photo, by the folder above it, so a
        // photo two folders deep still puts its grandparents in the tree.
        var subfolders: [String: Set<String>] = [:]
        for path in byFolder.keys where !path.isEmpty {
            var parent = ""
            for component in path.split(separator: "/") {
                let child = parent.isEmpty ? String(component) : parent + "/" + String(component)
                subfolders[parent, default: []].insert(child)
                parent = child
            }
        }

        /// The rows inside `path`, and how many photos are in it or below it.
        func build(_ path: String) -> (rows: [LibraryNode], photos: Int) {
            var rows: [LibraryNode] = []
            var count = 0

            for child in (subfolders[path] ?? []).sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
                let built = build(child)
                count += built.photos
                rows.append(
                    .folder(
                        LibraryNode.Folder(
                            path: child,
                            children: built.rows,
                            photoCount: built.photos,
                            id: root.appending(path: child)
                        )
                    )
                )
            }

            let own = (byFolder[path] ?? []).map(LibraryNode.photo)
            return (rows + own, count + own.count)
        }

        return build("").rows
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

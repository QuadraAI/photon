//
//  EditorViewModel.swift
//  Photon
//

import CoreGraphics
import CoreImage
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
/// which tool panel is open, and what has been done to the photo on show.
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
        case ready(PhotoItem, RenderedPhoto)
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

    /// What undoing and redoing would do, for the toolbar and the Edit menu to
    /// name. Read from the selected photo's session.
    private(set) var undoName: EditStepName?
    private(set) var redoName: EditStepName?

    /// The photo with the crop session's turn applied and nothing cropped from
    /// it: what the crop overlay is drawn over.
    ///
    /// Nil whenever the crop tool is shut. While it is open, a handle drag only
    /// moves the overlay — the picture underneath is left alone and the region
    /// outside the crop is dimmed, which is what makes a drag cost nothing.
    private(set) var sessionBase: CIImage?

    /// Guards the macOS window maximiser so it runs once per window instead of
    /// fighting a user who resizes afterwards.
    private(set) var hasMaximizedWindow = false

    private let logger = Logger(subsystem: "com.quadra.Photon", category: "EditorViewModel")
    private let libraryLoader: PhotoLibraryLoading
    private let renderer: PhotoEditing

    /// The folder currently loaded, so ``retry()`` knows what to re-scan.
    @ObservationIgnored private var folder: AuthorizedFolder?

    /// The in-flight decode, cancelled when the selection moves on.
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    /// The in-flight re-render after a commit or an undo.
    @ObservationIgnored private var renderTask: Task<Void, Never>?

    /// The in-flight render of a crop session's turned base image.
    @ObservationIgnored private var sessionBaseTask: Task<Void, Never>?

    /// One session per photo the user has edited or opened the crop tool on.
    ///
    /// Made on demand rather than per selection: a folder of ten thousand photos
    /// browsed once should not leave ten thousand histories behind, and a photo
    /// nobody has touched has nothing to record anyway.
    @ObservationIgnored private var sessions: [URL: PhotoEditSession] = [:]

    init(library: PhotoLibraryLoading, renderer: PhotoEditing) {
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
        renderTask?.cancel()
        sessionBaseTask?.cancel()
        selection = nil
        canvas = .nothingSelected
        openTool = nil
        sessionBase = nil
        // An edit belongs to a photo in this folder, and the window starts over
        // with it. Nothing here is written to disk yet, so a session that
        // outlived its folder would be a history of a photo the user has left.
        //
        // Dropping them is all it takes: a registered undo does not hold the
        // session it was registered against, so there is nothing to tear down.
        sessions.removeAll()
        // A filter belongs to the list it was typed against, and the window
        // starts over with it. Assigning it is also what re-derives the list.
        library = .loading
        filter = ""
        refreshUndoState()

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
        renderTask?.cancel()
        sessionBaseTask?.cancel()

        // Anything being cropped belongs to the photo being left, so it goes into
        // that photo's history first — where ⌘Z can still reach it on the way
        // back. The tool closes, because a crop is about one picture.
        commitCropSession(closePanel: openTool == .crop)
        // A colour change belongs to the photo being left too, but the panel stays
        // open: it is a tool rather than a session, and the next photo is very
        // often the one being graded next.
        commitColorSession()
        sessionBase = nil

        selection = item
        canvas = .loading(item)
        // Undo follows the photo rather than being thrown away with it: it is
        // read back from whichever session this photo has.
        refreshUndoState()

        let session = session(for: item)
        loadTask = Task { [renderer] in
            do {
                // The photo's own size first: a property read rather than a
                // decode, and the crop maths means nothing without it.
                let sourceSize = try await renderer.pixelSize(of: item.url)
                let recipe = session.displayedRecipe

                // What the file already carries, so the canvas has the picture on
                // it in about a millisecond instead of after a full decode — 700 ms
                // for one of a Sony's raw files. Only for a photo with nothing
                // done to it: the draft has no recipe applied, so on an edited
                // photo it would show the whole picture and then jump into the
                // crop.
                if recipe.isIdentity,
                   let draft = try? await renderer.draft(for: item.url, maxPixelSize: AppLayout.previewMaxPixelSize),
                   Self.isSameShape(draft, as: sourceSize) {
                    guard !Task.isCancelled else { return }
                    // The draft is pixels the file already carried, so it becomes
                    // Core Image's to draw like everything else the canvas shows.
                    let stand = CIImage(cgImage: draft)
                    canvas = .ready(item, RenderedPhoto(image: stand, base: stand, sourceSize: sourceSize))
                }

                let base = try await renderer.preview(item.url, recipe: .identity, maxPixelSize: AppLayout.previewMaxPixelSize)
                guard !Task.isCancelled else { return }

                var image = base
                if !recipe.isIdentity {
                    image = try await renderer.preview(item.url, recipe: recipe, maxPixelSize: AppLayout.previewMaxPixelSize)
                    guard !Task.isCancelled else { return }
                }

                canvas = .ready(item, RenderedPhoto(image: image, base: base, sourceSize: sourceSize))
            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Could not display \(item.name): \(String(describing: error))")
                canvas = .failed(item)
            }
        }
    }

    /// Whether a stand-in is the same shape as the photo it stands in for.
    ///
    /// The canvas lays the picture out from whichever image it is handed, so a
    /// stand-in of the wrong shape draws the photo at one size and then, when the
    /// render lands, at another — and the gap reads as bars that appear on the
    /// click and vanish once loading finishes. A file's preview is not always the
    /// picture's shape: a camera can write a letterboxed one, and an editor that
    /// saved over the file leaves its own behind at the crop *it* had.
    ///
    /// Half a per cent rather than equality, because a preview is rarely the
    /// photo's exact pixel size: 1616×1080 for a 3:2 photo is 0.25% out and
    /// passes, a 4:3 preview for that photo is 11% out and does not.
    private static func isSameShape(_ image: CGImage, as size: CGSize) -> Bool {
        guard size.width > 0, size.height > 0, image.height > 0 else { return false }

        let imageRatio = Double(image.width) / Double(image.height)
        let photoRatio = Double(size.width) / Double(size.height)

        return abs(imageRatio - photoRatio) / photoRatio < 0.005
    }

    /// ``beginSelecting(_:)``, then waits for the decode.
    ///
    /// The waiting is only useful to a caller that needs the photo on screen
    /// before carrying on, which in practice means tests.
    func select(_ item: PhotoItem) async {
        beginSelecting(item)
        await loadTask?.value
    }

    // MARK: - Cropping

    /// The crop being worked on, or nil when the crop tool is shut.
    var draftCrop: Crop? { currentSession?.draft }

    /// Whether the canvas should be drawing the crop overlay.
    var isCropping: Bool { openTool == .crop && currentSession?.draft != nil }

    /// The shape the crop is currently held to, for the panel's selection.
    var cropAspect: AspectRatio? { draftCrop?.aspect }

    /// Drags a crop handle to a point, in the overlay's own coordinates.
    ///
    /// The overlay is placed on the picture and sized to it, so a point inside it
    /// divided by its size is already a position in the photo — there is no fit
    /// calculation between the canvas and the crop, and so no way for the two to
    /// drift apart.
    func resizeCrop(moving edges: CropGeometry.Edges, to point: CGPoint) {
        guard let frame = cropFrame else { return }
        changeDraft { draft in
            draft.rect = CropGeometry.resized(
                draft.rect,
                moving: edges,
                to: point,
                aspect: draft.aspect,
                frame: frame
            )
        }
    }

    /// Moves the whole crop, from the rect its drag started on.
    ///
    /// Absolute rather than a step to add. `DragGesture` reports the whole
    /// translation on every callback, so adding it repeatedly walks the crop away
    /// from the finger; and the overlay re-renders between one callback and the
    /// next, so a step computed against the previous callback is computed against
    /// a state that has already been left behind. Taking the rect the drag began
    /// on and the distance it has travelled makes where the crop lands a function
    /// of where the finger is — the same answer however many callbacks arrived,
    /// and in whatever order.
    func moveCrop(from origin: CGRect, by delta: CGSize) {
        changeDraft { $0.rect = CropGeometry.moved(origin, by: delta) }
    }

    /// Holds the crop to a shape, growing or shrinking the one on screen to match.
    func setCropAspect(_ aspect: AspectRatio) {
        guard let frame = cropFrame else { return }
        changeDraft { draft in
            draft.rect = CropGeometry.fitted(aspect, inside: draft.rect, frame: frame)
            draft.aspect = aspect
        }
    }

    /// Turns the crop on its side: 16:9 becomes 9:16 over the same region.
    ///
    /// Meaningless without a pair to exchange, so a free crop ignores it.
    func swapCropOrientation() {
        guard let aspect = draftCrop?.aspect, !aspect.isFree else { return }
        setCropAspect(aspect.swapped)
    }

    /// Back to the photo as the file holds it: whole, and the right way up.
    func resetCrop() {
        currentSession?.updateDraft(.identity)
        updateSessionBase()
    }

    /// Turns the photo a quarter, keeping the crop over the region it was on.
    ///
    /// The ratio swaps with it, because it follows the pixels: the same region
    /// seen through a turned frame is the reciprocal shape.
    func rotateCrop(clockwise: Bool) {
        changeDraft { draft in
            draft.rect = CropGeometry.turned(draft.rect, by: clockwise ? .clockwise : .counterclockwise)
            draft.aspect = draft.aspect.swapped
            draft.rotation = clockwise ? draft.rotation.rotatedClockwise : draft.rotation.rotatedCounterclockwise
        }
        updateSessionBase()
    }

    /// How far `edge` currently sits from its own side of the frame.
    func cropInset(_ edge: CropGeometry.Edges) -> CGFloat {
        guard let rect = draftCrop?.rect else { return 0 }
        switch edge {
        case .left: return rect.minX
        case .right: return 1 - rect.maxX
        case .top: return rect.minY
        case .bottom: return 1 - rect.maxY
        default: return 0
        }
    }

    /// Sets one edge of the crop, as an inset from that edge of the frame.
    ///
    /// What the panel's four adjustable rows drive. A crop handle is a pointer
    /// affordance, and VoiceOver, Switch Control, Voice Control and Full Keyboard
    /// Access all need an operation they can perform rather than a target they
    /// can hit — so every crop this overlay can make is also makeable from the
    /// panel.
    func setCropInset(_ edge: CropGeometry.Edges, to inset: CGFloat) {
        let inset = min(max(0, inset), 1)
        let point: CGPoint
        switch edge {
        case .left: point = CGPoint(x: inset, y: 0)
        case .right: point = CGPoint(x: 1 - inset, y: 0)
        case .top: point = CGPoint(x: 0, y: inset)
        case .bottom: point = CGPoint(x: 0, y: 1 - inset)
        default: return
        }
        resizeCrop(moving: edge, to: point)
    }

    /// Commits the crop in progress, if there is one, as a single history step.
    ///
    /// Called from every way out of the tool, including the ones the user did not
    /// think of as leaving: clicking the rail, opening another tool, or picking a
    /// different photo. The step goes into that photo's history either way, so
    /// nothing is lost by any of them.
    func commitCropSession(closePanel: Bool = true) {
        let recorded = currentSession?.commit() ?? false
        updateSessionBase()
        if closePanel { openTool = nil }

        guard recorded else { return }
        refreshUndoState()
        reloadCanvas()
    }

    /// Escape, and Cancel: the draft is thrown away and no step is recorded.
    func abandonCropSession() {
        currentSession?.cancel()
        updateSessionBase()
        openTool = nil
    }

    // MARK: - Colour

    /// The context the engine stages previews with, and the one that has to
    /// draw them: see ``PhotoEditing/context``.
    var previewContext: CIContext { renderer.context }

    /// What the colour panel is showing: the drag in progress, or what the photo
    /// has been committed to.
    ///
    /// Read straight off the session, which is what makes the panel follow the
    /// canvas: `PhotoEditSession` is observable in its own right, so a view that
    /// reads this depends on the draft rather than on a copy of it kept here.
    var colorAdjustments: ColorAdjustments { currentSession?.displayedColor ?? .identity }

    /// Opens a colour change, so a whole drag is one step's worth of draft.
    ///
    /// Called when a slider is first touched rather than when the tool opens:
    /// the tool is a panel, and only a slider moved is an edit.
    func beginColorChange() {
        guard let item = selection else { return }
        session(for: item).beginColorSession()
    }

    /// Closes a colour change, committing whatever it moved as one step.
    ///
    /// Called when the drag ends, and — for a change made from the keyboard or
    /// VoiceOver, which has no drag to end — when the tool or the photo changes.
    func endColorChange() {
        commitColorSession()
    }

    func setSaturation(_ value: Double) {
        changeColor { $0.saturation = value }
    }

    func setVibrance(_ value: Double) {
        changeColor { $0.vibrance = value }
    }

    func setColorCast(_ value: Double) {
        changeColor { $0.colorCast = value }
    }

    /// One band's value in one mode.
    func setBand(_ channel: HSLChannel, _ band: ColorBand, to value: Double) {
        changeColor { $0[channel, in: band] = value }
    }

    /// Back to the photo's own colours, as a single step.
    func resetColor() {
        guard let item = selection else { return }
        let session = session(for: item)
        session.beginColorSession()
        session.updateColorDraft(.identity)
        commitColorSession()
    }

    /// Commits the colour change in progress, if there is one.
    ///
    /// Called from every way out of a change: the pointer being let go, the tool
    /// being swapped or shut, and the photo being left. A change nobody closed is
    /// still a change, and dropping it because the user clicked a rail icon
    /// rather than letting go of the mouse would be losing work to a
    /// technicality.
    ///
    /// The panel stays open, unlike the crop's: it is a tool rather than a
    /// session, and the next photo is very often the one being graded next.
    func commitColorSession() {
        guard currentSession?.commitColor() ?? false else { return }

        refreshUndoState()
        updateSessionBase()
        reloadCanvas()
    }

    /// Changes the colour in progress, in place, and puts it on the canvas.
    ///
    /// A copy with the field that changed set on it, rather than a fresh value
    /// built from the fields that did not: a slider added later cannot be quietly
    /// dropped by a call site that never heard of it.
    private func changeColor(_ change: (inout ColorAdjustments) -> Void) {
        guard var draft = currentSession?.colorDraft else { return }
        change(&draft)
        currentSession?.updateColorDraft(draft)
        reloadCanvas()
    }

    /// Waits for the canvas to have caught up with whatever was last asked of it.
    ///
    /// Only a caller that needs the picture settled before carrying on needs this,
    /// which in practice means tests — the same reason ``select(_:)`` waits for its
    /// decode. The app never waits: the canvas holds the picture it has until the
    /// new one is ready, which is what should happen.
    ///
    /// Waiting means waiting for the *last* render, not the one in flight: a
    /// render held back to the cadence starts its successor on the way out, so
    /// one that was awaited can already have been replaced by the time it is
    /// done.
    func waitForCanvas() async {
        await loadTask?.value
        while isRendering, let renderTask {
            await renderTask.value
        }
        await sessionBaseTask?.value
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
    ///
    /// Leaving either editing tool commits what it was in the middle of. For the
    /// crop that is the only way out a user who has just spent a minute on a
    /// handle drag will actually take, and silently dropping that work because
    /// they clicked an icon rather than a button would be losing it to a
    /// technicality. Escape and Cancel are the ways to say no.
    func toggleTool(_ tool: Tool) {
        let isClosing = openTool == tool
        commitCropSession(closePanel: false)
        commitColorSession()

        guard !isClosing else {
            openTool = nil
            // Any tool but the crop lets the working picture go with it.
            updateSessionBase()
            return
        }

        openTool = tool
        if tool == .crop {
            beginCropSession()
        } else {
            updateSessionBase()
        }
    }

    /// Clamped here, so a drag that runs off the end of the range is absorbed
    /// rather than banked.
    func setPanelWidth(_ width: CGFloat) {
        panelWidth = width.clamped(to: AppLayout.toolPanelWidthRange)
    }

    // MARK: - Undo

    func undo() {
        guard let session = currentSession, session.canUndo else { return }
        session.undo()
        historyDidMove()
    }

    func redo() {
        guard let session = currentSession, session.canRedo else { return }
        session.redo()
        historyDidMove()
    }

    // MARK: - Window

    func markWindowMaximized() {
        hasMaximizedWindow = true
    }

    // MARK: - Sessions

    /// The session for `item`, made on first use.
    private func session(for item: PhotoItem) -> PhotoEditSession {
        if let existing = sessions[item.url] { return existing }
        let session = PhotoEditSession(photo: item)
        sessions[item.url] = session
        return session
    }

    /// The selected photo's session, or nil when it has none yet.
    ///
    /// Deliberately does not create one: reading undo state must not be what
    /// brings a history into being, or browsing a folder would leave a session
    /// behind on every photo the user clicked past.
    private var currentSession: PhotoEditSession? {
        guard let selection else { return nil }
        return sessions[selection.url]
    }

    /// The photo on the canvas, if it has finished rendering.
    private var renderedPhoto: RenderedPhoto? {
        if case .ready(_, let photo) = canvas { return photo }
        return nil
    }

    /// The frame a crop of the selected photo lives in.
    private var cropFrame: CGSize? {
        guard let sourceSize = renderedPhoto?.sourceSize, let rotation = draftCrop?.rotation else { return nil }
        return CropGeometry.turnedSize(sourceSize, by: rotation)
    }

    private func beginCropSession() {
        guard let item = selection else { return }
        session(for: item).beginCropSession()
        updateSessionBase()
        refreshUndoState()
    }

    /// Changes the crop in progress, in place.
    ///
    /// A copy with the fields that changed set on it, rather than a fresh `Crop`
    /// built from the ones that did not: a field added later cannot be quietly
    /// dropped by a call site that never heard of it.
    private func changeDraft(_ change: (inout Crop) -> Void) {
        guard var draft = currentSession?.draft else { return }
        change(&draft)
        currentSession?.updateDraft(draft)
    }

    /// Works out the picture the crop overlay sits on: the photo turned a
    /// quarter, with the colours it is being shown in, and nothing cropped from
    /// it.
    ///
    /// Nil whenever there is nothing the canvas does not already have — no turn,
    /// and no colour change — in which case the canvas falls back to the photo's
    /// own untaken frame, which is already the thing. So this is also how a
    /// session is let go, and there is one way to say it rather than two that have
    /// to agree.
    ///
    /// The colours are the reason this is here at all now. A crop handle is
    /// dragged over the picture, so a photo that has been graded has to have its
    /// crop dragged over the grade rather than over the file's own pixels — and
    /// the untaken frame the canvas kept is the photo as it arrived.
    ///
    /// A handle drag never gets here: the overlay moves and the picture stays put.
    /// Only a turn changes what is underneath, and a turn is a button rather than
    /// a drag, so one render per press is affordable. Without it a quarter turn
    /// would move the crop rect over a picture that had not moved with it.
    ///
    /// Nothing is rendered unless the crop tool is open, because nothing reads
    /// the picture unless the crop tool is open — the canvas only reaches for a
    /// working picture while the overlay is on it. A colour change committed with
    /// the crop tool shut used to render one at preview size that no one would
    /// look at; the tool opening is what asks for it.
    private func updateSessionBase() {
        sessionBaseTask?.cancel()

        guard isCropping, let item = selection else {
            // Let the picture go with the tool: it is a preview's worth of
            // pixels, and the next opening renders its own.
            sessionBase = nil
            return
        }

        let rotation = draftCrop?.rotation ?? .none
        let color = colorAdjustments
        guard rotation != .none || !color.isIdentity else {
            sessionBase = nil
            return
        }

        let recipe = EditRecipe(
            crop: Crop(rect: CropGeometry.unitFrame, aspect: .free, rotation: rotation),
            color: color
        )

        sessionBaseTask = Task { [renderer] in
            guard let image = try? await renderer.preview(
                item.url,
                recipe: recipe,
                maxPixelSize: AppLayout.previewMaxPixelSize
            ) else { return }

            // A second press of Rotate, or a colour that moved on while this was
            // rendering, supersedes it: the newer picture is the one the overlay
            // has been moved to match.
            guard !Task.isCancelled,
                  selection?.url == item.url,
                  (draftCrop?.rotation ?? .none) == rotation,
                  colorAdjustments == color
            else { return }
            sessionBase = image
        }
    }

    /// After anything that moved the history: the mirror, the canvas, and the
    /// crop tool if the move took its draft out from under it.
    private func historyDidMove() {
        refreshUndoState()
        // Undoing past the point a crop began leaves nothing for the overlay to
        // draw, so the tool closes rather than showing a draft the history has
        // no record of.
        if draftCrop == nil, openTool == .crop { openTool = nil }
        updateSessionBase()
        reloadCanvas()
    }

    /// Whether a render is on its way, and whether another was asked for while it
    /// was.
    ///
    /// A slider drag asks for a picture per value, faster than a screen takes
    /// frames. Cancelling and restarting for each of them spends a whole render
    /// only to throw it away, and puts a task, an actor hop and a canvas
    /// assignment on the main thread for every value the pointer produced — none
    /// of which is work anybody sees, because the screen took one frame out of
    /// it. One render in flight, with the newest value waiting behind it, is the
    /// same picture on screen a frame later for a fraction of the work.
    @ObservationIgnored private var isRendering = false
    @ObservationIgnored private var isRenderPending = false

    /// When the last render began, which is what the cadence is measured from.
    ///
    /// Nil until the canvas has rendered once, so the first picture is never
    /// held back by a cadence that has not begun.
    @ObservationIgnored private var lastRenderBegan: ContinuousClock.Instant?

    /// Re-renders the canvas from the selected photo's current recipe.
    ///
    /// Every commit, undo and redo lands here: one render per history move, which
    /// is exactly what a handle drag never has to do. A slider drag lands here
    /// for every value it passes through, and the queue above is only half of
    /// what makes that affordable — the other half is the cadence below, which
    /// is what stops a drag from asking for more pictures than the screen has
    /// frames.
    private func reloadCanvas() {
        guard !isRendering else {
            isRenderPending = true
            return
        }

        guard let item = selection, let photo = renderedPhoto else { return }

        // One render at a time, and the guard above is what keeps it to one: a
        // task stops being the current one by finishing, and it clears the flag
        // in its own `defer`, so nothing here has to cancel anything.
        isRendering = true

        renderTask = Task { [renderer] in
            defer {
                isRendering = false
                if isRenderPending {
                    isRenderPending = false
                    reloadCanvas()
                }
            }

            // Held to the screen's rate. A value that arrives sooner than a
            // frame can show it waits the rest of the interval rather than being
            // rendered into a frame nobody sees, and the wait is also where a
            // burst collapses: the recipe is read *after* it, so a value that
            // arrived while this one was waiting is the value that lands.
            let rate = AppLayout.displayRefreshRate
            let now = ContinuousClock.now
            if let began = lastRenderBegan,
               !RenderPacing.shouldRender(now: now, lastRendered: began, refreshRate: rate) {
                try? await Task.sleep(for: RenderPacing.interval(refreshRate: rate) - (now - began))
                guard !Task.isCancelled else { return }
            }

            // Everything asked for up to here is in the recipe below, so the
            // flag is settled rather than left to fetch a second render of the
            // same picture. Anything asked for after it is a request this render
            // cannot answer, and the `defer` takes it.
            isRenderPending = false
            lastRenderBegan = ContinuousClock.now

            let recipe = currentSession?.displayedRecipe ?? .identity
            do {
                let image = try await renderer.preview(item.url, recipe: recipe, maxPixelSize: AppLayout.previewMaxPixelSize)
                guard !Task.isCancelled, selection?.url == item.url else { return }
                canvas = .ready(item, RenderedPhoto(image: image, base: photo.base, sourceSize: photo.sourceSize))
            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Could not render \(item.name): \(String(describing: error))")
                canvas = .failed(item)
            }
        }
    }

    /// Mirrors the selected photo's undo state.
    ///
    /// `UndoManager` is not observable and the session it belongs to changes with
    /// the selection, so the toolbar reads these rather than reaching through.
    private func refreshUndoState() {
        canUndo = currentSession?.canUndo ?? false
        canRedo = currentSession?.canRedo ?? false
        undoName = currentSession?.undoName
        redoName = currentSession?.redoName
    }
}

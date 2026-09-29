//
//  EditorViewModelTests.swift
//  PhotonTests
//

import CoreGraphics
import Foundation
import Testing

@testable import Photon

@Suite("Editor view model")
@MainActor
struct EditorViewModelTests {
    // MARK: - Loading a folder

    @Test("Loading a folder lists its photos")
    func loadListsPhotos() async {
        let photos = [PhotoItem.fixture(name: "a.jpg"), PhotoItem.fixture(name: "b.jpg")]
        let editor = makeEditor(library: StubPhotoLibrary(photos: photos))

        await editor.load(.fixture())

        #expect(editor.library == .loaded(photos))
    }

    @Test("An empty folder is a normal result, not a failure")
    func emptyFolderLoads() async {
        let editor = makeEditor(library: StubPhotoLibrary(photos: []))

        await editor.load(.fixture())

        #expect(editor.library == .loaded([]))
    }

    @Test("An unreadable folder is reported")
    func unreadableFolderFails() async {
        let editor = makeEditor(library: StubPhotoLibrary(failure: .unreadable))

        await editor.load(.fixture())

        #expect(editor.library == .failed(.unreadable))
    }

    @Test("Loading the folder already on show does not scan again")
    func loadingTheSameFolderIsIdempotent() async {
        let library = StubPhotoLibrary(photos: [.fixture()])
        let editor = makeEditor(library: library)

        await editor.load(.fixture())
        await editor.load(.fixture())

        #expect(library.scanCount == 1)
    }

    @Test("Loading a different folder scans again")
    func loadingAnotherFolderRescans() async {
        let library = StubPhotoLibrary(photos: [.fixture()])
        let editor = makeEditor(library: library)

        await editor.load(.fixture())
        await editor.load(.fixture(name: "Other"))

        #expect(library.scanCount == 2)
    }

    @Test("Retrying after a failure scans again")
    func retryRescans() async {
        let library = StubPhotoLibrary(failure: .unreadable)
        let editor = makeEditor(library: library)
        await editor.load(.fixture())

        await editor.retry()

        #expect(library.scanCount == 2)
    }

    @Test("A cancelled walk is not mistaken for an empty folder")
    func cancelledScanDoesNotPublish() async {
        let editor = makeEditor(library: StubPhotoLibrary(photos: [.fixture()], delay: .milliseconds(50)))

        let loading = Task { await editor.load(.fixture()) }
        // Let the load start, then take the walk away from it.
        await Task.yield()
        loading.cancel()
        await loading.value

        #expect(editor.library == .loading)
    }

    @Test("Loading clears the previous folder's selection, canvas and open tool")
    func loadResetsState() async {
        let editor = makeEditor(library: StubPhotoLibrary(photos: [.fixture()]))
        await editor.load(.fixture())
        await editor.select(.fixture())
        editor.toggleTool(.color)

        await editor.load(.fixture(name: "Other"))

        #expect(editor.selection == nil)
        #expect(editor.openTool == nil)
        #expect(editor.isShowingNothing)
    }

    // MARK: - Selecting a photo

    @Test("Selecting a photo decodes it and puts it on the canvas")
    func selectingRendersThePhoto() async {
        let photo = PhotoItem.fixture()
        let renderer = StubPhotoRenderer()
        let editor = makeEditor(renderer: renderer)

        await editor.select(photo)

        #expect(editor.selection == photo)
        #expect(editor.decodedPhoto == photo)
        #expect(renderer.requestedURLs == [photo.url])
    }

    @Test("A photo that cannot be decoded is reported and stays selected")
    func unreadablePhotoFails() async {
        let photo = PhotoItem.fixture()
        let editor = makeEditor(renderer: StubPhotoRenderer(failure: .unreadable))

        await editor.select(photo)

        #expect(editor.failedPhoto == photo)
        #expect(editor.selection == photo, "A photo that will not decode is still the one being looked at")
    }

    @Test("Selecting highlights straight away, before the decode finishes")
    func selectingHighlightsImmediately() async {
        let photo = PhotoItem.fixture()
        let editor = makeEditor(renderer: StubPhotoRenderer(delay: .milliseconds(50)))

        // What the sidebar's selection binding does on click.
        editor.beginSelecting(photo)

        #expect(editor.selection == photo)
        #expect(editor.loadingPhoto == photo)
    }

    @Test("The file's own preview reaches the canvas before the decode does")
    func draftReachesTheCanvasFirst() async {
        let photo = PhotoItem.fixture()
        // A draft that is instant and a decode that is not: what the canvas shows
        // in between is the whole point of asking for one.
        let renderer = StubPhotoRenderer(delay: .milliseconds(50))
        let editor = makeEditor(renderer: renderer)

        editor.beginSelecting(photo)
        await Task.yield()

        #expect(renderer.draftURLs == [photo.url])
        #expect(editor.decodedPhoto == photo, "The decode has not finished yet")
    }

    @Test("A slower earlier decode cannot land on top of a later selection")
    func selectingAgainCancelsTheFirstDecode() async {
        let first = PhotoItem.fixture(name: "first.jpg")
        let second = PhotoItem.fixture(name: "second.jpg")
        let editor = makeEditor(renderer: StubPhotoRenderer(delay: .milliseconds(50)))

        let slow = Task { await editor.select(first) }
        await Task.yield()
        await editor.select(second)
        await slow.value

        #expect(editor.decodedPhoto == second)
    }

    // MARK: - Tools

    @Test("The rail starts with no panel open")
    func noToolOpenInitially() {
        #expect(makeEditor().openTool == nil)
    }

    @Test("Toggling a tool opens its panel, closes it, and swaps it")
    func togglingTools() {
        let editor = makeEditor()

        editor.toggleTool(.light)
        #expect(editor.openTool == .light)

        editor.toggleTool(.light)
        #expect(editor.openTool == nil, "The tool that is open closes")

        editor.toggleTool(.light)
        editor.toggleTool(.crop)
        #expect(editor.openTool == .crop, "Another tool swaps the panel rather than closing it")
    }

    // MARK: - Undo

    @Test("Nothing can be undone until an edit is recorded")
    func undoStartsDisabled() {
        let editor = makeEditor()

        #expect(editor.canUndo == false)
        #expect(editor.canRedo == false)
    }

    @Test("Recording an edit enables undo, and undoing enables redo")
    func undoAndRedoCycle() {
        let editor = makeEditor()
        var value = 0

        editor.registerEdit(apply: { value = 1 }, revert: { value = 0 })
        #expect(editor.canUndo)

        editor.undo()
        #expect(value == 0)
        #expect(editor.canRedo)
        #expect(editor.canUndo == false)

        editor.redo()
        #expect(value == 1)
        #expect(editor.canUndo, "Redoing must leave the edit undoable again")
    }

    @Test("Switching photos clears the undo history")
    func selectingAnotherPhotoClearsUndo() async {
        let editor = makeEditor(library: StubPhotoLibrary(photos: [.fixture(), .fixture(name: "b.jpg")]))
        await editor.load(.fixture())
        editor.registerEdit(apply: {}, revert: {})
        #expect(editor.canUndo)

        await editor.select(.fixture(name: "b.jpg"))

        // Otherwise ⌘Z would silently revert an edit to a photo no longer shown.
        #expect(editor.canUndo == false)
        #expect(editor.canRedo == false)
    }

    // MARK: - Filtering

    @Test("A filter that is empty, or only whitespace, shows every photo")
    func noFilterShowsEverything() async {
        let photos = [PhotoItem.fixture(name: "a.jpg"), PhotoItem.fixture(name: "b.jpg")]
        let editor = makeEditor(library: StubPhotoLibrary(photos: photos))
        await editor.load(.fixture())

        #expect(editor.matches == photos)
        #expect(editor.isFilteringToNothing == false)

        editor.filter = "   "

        #expect(editor.matches == photos)
        #expect(editor.isFilteringToNothing == false)
    }

    @Test("Filtering matches part of a name, ignoring case")
    func filterMatchesLoosely() async {
        let photos = [
            PhotoItem.fixture(name: "Sunset.jpg"),
            PhotoItem.fixture(name: "Portrait.jpg"),
        ]
        let editor = makeEditor(library: StubPhotoLibrary(photos: photos))
        await editor.load(.fixture())

        editor.filter = "SUN"

        #expect(editor.matches.map(\.name) == ["Sunset.jpg"])
    }

    @Test("A filter matching nothing is distinguishable from an empty folder")
    func filterCanMatchNothing() async {
        let editor = makeEditor(library: StubPhotoLibrary(photos: [.fixture()]))
        await editor.load(.fixture())

        editor.filter = "nothing-like-this"

        #expect(editor.matches.isEmpty)
        #expect(editor.isFilteringToNothing)
    }

    @Test("Loading another folder clears the filter")
    func loadingClearsTheFilter() async {
        let editor = makeEditor(library: StubPhotoLibrary(photos: [.fixture()]))
        await editor.load(.fixture())
        editor.filter = "a"

        await editor.load(.fixture(name: "Other"))

        #expect(editor.filter.isEmpty)
    }

    // MARK: - The listed tree

    @Test("A folder's photos are listed under it, folders before photos")
    func listsPhotosUnderTheirFolder() async throws {
        let editor = makeEditor(
            library: StubPhotoLibrary(photos: [
                .fixture(name: "root.jpg"),
                .fixture(name: "delta.jpg", subfolderPath: "Subfolder"),
                .fixture(name: "gamma.png", subfolderPath: "Subfolder"),
                .fixture(name: "beta.png", subfolderPath: "Holiday"),
            ])
        )
        await editor.load(.fixture())

        // Two folders, then the one photo that sits in the root.
        #expect(editor.nodes.map(\.name) == ["Holiday", "Subfolder", "root.jpg"])

        let subfolder = try #require(folder(editor.nodes.first { $0.name == "Subfolder" }))
        #expect(subfolder.children.map(\.name) == ["delta.jpg", "gamma.png"])
        #expect(subfolder.photoCount == 2)
    }

    @Test("A folder of folders is a tree, and counts everything below it")
    func nestsFolders() async throws {
        let editor = makeEditor(
            library: StubPhotoLibrary(photos: [
                .fixture(name: "delta.jpg", subfolderPath: "Holiday/Sub"),
                .fixture(name: "gamma.png", subfolderPath: "Holiday/Sub"),
            ])
        )
        await editor.load(.fixture())

        // The folder with no photos of its own holds only the folder below it,
        // which is what a camera's `100MSDCF`-style dump looks like.
        let holiday = try #require(folder(editor.nodes.first))
        #expect(holiday.name == "Holiday")
        #expect(holiday.children.map(\.name) == ["Sub"])
        #expect(holiday.photoCount == 2, "A folder counts what is below it")

        let sub = try #require(folder(holiday.children.first))
        #expect(sub.name == "Sub")
        #expect(sub.children.map(\.name) == ["delta.jpg", "gamma.png"])
    }

    @Test("Filtering leaves only the folders that still hold a match")
    func filterPrunesTheTree() async {
        let editor = makeEditor(
            library: StubPhotoLibrary(photos: [
                .fixture(name: "Sunset.jpg", subfolderPath: "Holiday"),
                .fixture(name: "Portrait.jpg", subfolderPath: "Studio"),
            ])
        )
        await editor.load(.fixture())
        #expect(editor.nodes.map(\.name) == ["Holiday", "Studio"])

        editor.filter = "Sunset"

        #expect(editor.nodes.map(\.name) == ["Holiday"], "A folder with no match is not listed")
        #expect(editor.matches.count == 1)
    }

    @Test("A row's id finds its photo, and a folder's finds nothing")
    func lookUpByNodeID() async throws {
        let photo = PhotoItem.fixture(name: "delta.jpg", subfolderPath: "Subfolder")
        let editor = makeEditor(library: StubPhotoLibrary(photos: [photo]))
        await editor.load(.fixture())

        #expect(editor.photo(withNodeID: photo.url) == photo)

        let subfolder = try #require(folder(editor.nodes.first))
        #expect(editor.photo(withNodeID: subfolder.id) == nil, "A folder's row is not a photo")
    }

    // MARK: - Resizing

    // Only the tool panel is ours to clamp. The sidebar's width belongs to the
    // split view, which is handed the same range.

    @Test("The tool panel opens at its default width")
    func panelStartsAtItsDefaultWidth() {
        let editor = makeEditor()

        #expect(editor.panelWidth == AppLayout.toolPanelWidth)
    }

    @Test("The tool panel can be dragged anywhere inside its range")
    func panelResizesWithinRange() {
        let editor = makeEditor()
        let range = AppLayout.toolPanelWidthRange

        editor.setPanelWidth(range.lowerBound + 10)
        #expect(editor.panelWidth == range.lowerBound + 10)

        editor.setPanelWidth(range.upperBound - 10)
        #expect(editor.panelWidth == range.upperBound - 10)
    }

    @Test("Dragging the tool panel past a limit is absorbed, not banked")
    func panelClampsAtItsLimits() {
        let editor = makeEditor()
        let panel = AppLayout.toolPanelWidthRange

        editor.setPanelWidth(10_000)
        #expect(editor.panelWidth == panel.upperBound)

        editor.setPanelWidth(-10_000)
        #expect(editor.panelWidth == panel.lowerBound)
    }

    @Test("Coming back from past a limit tracks the pointer again")
    func clampingDoesNotLagThePointer() {
        let editor = makeEditor()
        let range = AppLayout.toolPanelWidthRange

        // What a drag far past the minimum and part-way back does.
        editor.setPanelWidth(range.lowerBound - 500)
        editor.setPanelWidth(range.lowerBound + 40)

        #expect(editor.panelWidth == range.lowerBound + 40)
    }

    // MARK: - Window

    @Test("Maximising is recorded once and does not reverse")
    func maximizingIsOneWay() {
        let editor = makeEditor()
        #expect(editor.hasMaximizedWindow == false)

        editor.markWindowMaximized()

        #expect(editor.hasMaximizedWindow)
    }

    // MARK: - Helpers

    private func makeEditor(
        library: StubPhotoLibrary = StubPhotoLibrary(),
        renderer: StubPhotoRenderer = StubPhotoRenderer()
    ) -> EditorViewModel {
        EditorViewModel(library: library, renderer: renderer)
    }

    /// The folder a node is, or nil when it is a photo.
    private func folder(_ node: LibraryNode?) -> LibraryNode.Folder? {
        if case .folder(let folder) = node { return folder }
        return nil
    }
}

// The canvas is one state at a time, and a test is about one of them: these read
// as the case under test, and are nil for the other three.
private extension EditorViewModel {
    /// The photo the canvas has decoded.
    var decodedPhoto: PhotoItem? {
        if case .ready(let photo, _) = canvas { return photo }
        return nil
    }

    /// The photo the canvas is waiting on.
    var loadingPhoto: PhotoItem? {
        if case .loading(let photo) = canvas { return photo }
        return nil
    }

    /// The photo the canvas could not decode.
    var failedPhoto: PhotoItem? {
        if case .failed(let photo) = canvas { return photo }
        return nil
    }

    /// Whether the canvas has nothing to show at all.
    var isShowingNothing: Bool {
        if case .nothingSelected = canvas { return true }
        return false
    }
}

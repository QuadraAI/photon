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

        // A cancelled walk reports no photos, so this must not read as an empty
        // folder.
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
        guard case .nothingSelected = editor.canvas else {
            Issue.record("Expected an empty canvas, got \(editor.canvas)")
            return
        }
    }

    // MARK: - Selecting a photo

    @Test("Selecting a photo puts it on the canvas")
    func selectingRendersThePhoto() async {
        let photo = PhotoItem.fixture()
        let renderer = StubPhotoRenderer()
        let editor = makeEditor(renderer: renderer)

        await editor.select(photo)

        #expect(editor.selection == photo)
        guard case .ready(let shown, _) = editor.canvas else {
            Issue.record("Expected a rendered photo, got \(editor.canvas)")
            return
        }
        #expect(shown == photo)
        #expect(renderer.requestedURLs == [photo.url])
    }

    @Test("A photo that cannot be decoded is reported and stays selected")
    func unreadablePhotoFails() async {
        let photo = PhotoItem.fixture()
        let editor = makeEditor(renderer: StubPhotoRenderer(failure: .unreadable))

        await editor.select(photo)

        guard case .failed(let failed) = editor.canvas else {
            Issue.record("Expected a failure, got \(editor.canvas)")
            return
        }
        #expect(failed == photo)
        #expect(editor.selection == photo, "A photo that will not decode is still the one being looked at")
    }

    @Test("Selecting highlights straight away, before the decode finishes")
    func selectingHighlightsImmediately() async {
        let photo = PhotoItem.fixture()
        let editor = makeEditor(renderer: StubPhotoRenderer(delay: .milliseconds(50)))

        // What the sidebar's selection binding does on click.
        editor.beginSelecting(photo)

        #expect(editor.selection == photo)
        guard case .loading(let loading) = editor.canvas else {
            Issue.record("Expected the canvas to be loading at once, got \(editor.canvas)")
            return
        }
        #expect(loading == photo)
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

        guard case .ready(let shown, _) = editor.canvas else {
            Issue.record("Expected a rendered photo, got \(editor.canvas)")
            return
        }
        #expect(shown == second)
    }

    // MARK: - Tools

    @Test("The rail starts with no panel open")
    func noToolOpenInitially() {
        #expect(makeEditor().openTool == nil)
    }

    @Test("Toggling a tool opens its panel")
    func togglingOpensThePanel() {
        let editor = makeEditor()

        editor.toggleTool(.light)

        #expect(editor.openTool == .light)
    }

    @Test("Toggling the open tool closes it again")
    func togglingTheSameToolCloses() {
        let editor = makeEditor()
        editor.toggleTool(.light)

        editor.toggleTool(.light)

        #expect(editor.openTool == nil)
    }

    @Test("Toggling a different tool swaps the panel rather than closing it")
    func togglingAnotherToolSwaps() {
        let editor = makeEditor()
        editor.toggleTool(.light)

        editor.toggleTool(.crop)

        #expect(editor.openTool == .crop)
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

    @Test("An empty filter shows every photo")
    func emptyFilterShowsEverything() async {
        let photos = [PhotoItem.fixture(name: "a.jpg"), PhotoItem.fixture(name: "b.jpg")]
        let editor = makeEditor(library: StubPhotoLibrary(photos: photos))
        await editor.load(.fixture())

        #expect(editor.visiblePhotos == photos)
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

        #expect(editor.visiblePhotos.map(\.name) == ["Sunset.jpg"])
    }

    @Test("A filter matching nothing is distinguishable from an empty folder")
    func filterCanMatchNothing() async {
        let editor = makeEditor(library: StubPhotoLibrary(photos: [.fixture()]))
        await editor.load(.fixture())

        editor.filter = "nothing-like-this"

        #expect(editor.visiblePhotos.isEmpty)
        // Worth telling apart: an empty folder is a normal state, a filter that
        // hides everything is something the user just did.
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

    @Test("A filter that only holds whitespace is treated as no filter")
    func blankFilterIsNoFilter() async {
        let photos = [PhotoItem.fixture(name: "a.jpg")]
        let editor = makeEditor(library: StubPhotoLibrary(photos: photos))
        await editor.load(.fixture())

        editor.filter = "   "

        #expect(editor.visiblePhotos == photos)
        #expect(editor.isFilteringToNothing == false)
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
        EditorViewModel(app: makeAppViewModel(), library: library, renderer: renderer)
    }
}

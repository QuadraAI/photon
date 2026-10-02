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
        let renderer = StubPhotoEditor()
        let editor = makeEditor(renderer: renderer)

        await editor.select(photo)

        #expect(editor.selection == photo)
        #expect(editor.decodedPhoto == photo)
        #expect(renderer.requestedURLs == [photo.url])
    }

    @Test("A photo that cannot be decoded is reported and stays selected")
    func unreadablePhotoFails() async {
        let photo = PhotoItem.fixture()
        let editor = makeEditor(renderer: StubPhotoEditor(failure: .unreadable))

        await editor.select(photo)

        #expect(editor.failedPhoto == photo)
        #expect(editor.selection == photo, "A photo that will not decode is still the one being looked at")
    }

    @Test("Selecting highlights straight away, before the decode finishes")
    func selectingHighlightsImmediately() async {
        let photo = PhotoItem.fixture()
        let editor = makeEditor(renderer: StubPhotoEditor(delay: .milliseconds(50)))

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
        let renderer = StubPhotoEditor(delay: .milliseconds(50))
        let editor = makeEditor(renderer: renderer)

        editor.beginSelecting(photo)
        await Task.yield()

        #expect(renderer.draftURLs == [photo.url])
        #expect(editor.decodedPhoto == photo, "The decode has not finished yet")
    }

    @Test("A preview that is not the photo's shape is left off the canvas")
    func aWrongShapedDraftNeverReachesTheCanvas() async {
        // What a file saved over by another editor carries: a preview of the
        // picture *it* had. Showing it draws the photo at one size and then, when
        // the render lands, at another — and the gap reads as bars appearing on
        // the click and vanishing once loading finishes.
        let photo = PhotoItem.fixture()
        let renderer = StubPhotoEditor(
            draft: CGImage.sized(width: 32, height: 32),
            size: CGSize(width: 4000, height: 3000),
            delay: .milliseconds(50)
        )
        let editor = makeEditor(renderer: renderer)

        editor.beginSelecting(photo)
        await Task.yield()

        #expect(renderer.draftURLs == [photo.url], "It was still worth asking for — the answer is what is wrong")
        #expect(editor.loadingPhoto == photo, "The wrong-shaped stand-in must not reach the canvas")

        await editor.waitForCanvas()
        #expect(editor.decodedPhoto == photo, "And the render still arrives")
    }

    @Test("A preview a little out of shape is still worth showing")
    func aSlightlyDifferentDraftIsShown() async {
        // What a camera writes: a preview rarely the photo's exact pixel size.
        // 1616×1080 for a 3:2 photo is a quarter of a per cent out, which is not a
        // discrepancy the user can see, and turning it away would cost them the
        // instant picture for nothing.
        let photo = PhotoItem.fixture()
        let renderer = StubPhotoEditor(
            draft: CGImage.sized(width: 1616, height: 1080),
            size: CGSize(width: 6000, height: 4000),
            delay: .milliseconds(50)
        )
        let editor = makeEditor(renderer: renderer)

        editor.beginSelecting(photo)
        await Task.yield()

        #expect(editor.decodedPhoto == photo, "The stand-in should be on the canvas already")
    }

    @Test("A slower earlier decode cannot land on top of a later selection")
    func selectingAgainCancelsTheFirstDecode() async {
        let first = PhotoItem.fixture(name: "first.jpg")
        let second = PhotoItem.fixture(name: "second.jpg")
        let editor = makeEditor(renderer: StubPhotoEditor(delay: .milliseconds(50)))

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
        #expect(editor.undoName == nil)
    }

    @Test("Cropping and committing enables undo, and undoing enables redo")
    func undoAndRedoCycle() async {
        let editor = await editorWithCropOpen()

        editor.setCropAspect(.fixed(width: 16, height: 9))
        editor.commitCropSession()
        #expect(editor.canUndo)
        #expect(editor.undoName == .crop(.fixed(width: 16, height: 9)), "The button names what it will take back")

        editor.undo()
        #expect(editor.canRedo)
        #expect(editor.canUndo == false)
        #expect(editor.undoName == nil)

        editor.redo()
        #expect(editor.canUndo, "Redoing must leave the edit undoable again")
        #expect(editor.redoName == nil)
    }

    @Test("Undoing past the start of a crop closes the tool")
    func undoPastTheStartOfACropClosesTheTool() async {
        let editor = await editorWithCropOpen()
        editor.setCropAspect(.fixed(width: 1, height: 1))
        editor.commitCropSession()
        editor.toggleTool(.crop)

        editor.undo()

        #expect(editor.openTool == nil, "There is no draft left for the overlay to draw")
        #expect(editor.isCropping == false)
    }

    @Test("Shutting the tool with a crop in progress commits it")
    func shuttingTheToolCommits() async {
        let editor = await editorWithCropOpen()

        editor.setCropAspect(.fixed(width: 1, height: 1))
        editor.toggleTool(.crop)

        #expect(editor.openTool == nil)
        #expect(editor.canUndo, "The work went into the history rather than being thrown away")
    }

    @Test("Cancelling throws the crop away and costs no step")
    func cancellingCropsCostsNothing() async {
        let editor = await editorWithCropOpen()

        editor.setCropAspect(.fixed(width: 1, height: 1))
        editor.abandonCropSession()

        #expect(editor.openTool == nil)
        #expect(editor.canUndo == false)
        #expect(editor.canRedo == false)
    }

    @Test("Switching photos keeps each one's history, and ⌘Z stays within the photo on screen")
    func historiesFollowTheirPhoto() async {
        let first = PhotoItem.fixture(name: "first.jpg")
        let second = PhotoItem.fixture(name: "second.jpg")
        let editor = makeEditor(library: StubPhotoLibrary(photos: [first, second]))
        await editor.load(.fixture())

        await editor.select(first)
        editor.toggleTool(.crop)
        editor.setCropAspect(.fixed(width: 1, height: 1))
        editor.commitCropSession()
        await editor.waitForCanvas()

        await editor.select(second)
        #expect(editor.canUndo == false, "The second photo has nothing done to it")
        #expect(editor.undoName == nil)

        editor.toggleTool(.crop)
        editor.setCropAspect(.fixed(width: 4, height: 5))
        editor.commitCropSession()
        await editor.waitForCanvas()

        // Back to the first: its own history is still there, and ⌘Z reaches it
        // rather than the second photo's.
        await editor.select(first)
        #expect(editor.canUndo)
        #expect(editor.undoName == .crop(.fixed(width: 1, height: 1)), "Not the other photo's crop")

        editor.undo()
        #expect(editor.canUndo == false, "One step was recorded here, so one undo clears it")
    }

    @Test("Leaving a photo with a crop open commits it into that photo's history")
    func leavingAPhotoCommitsItsCrop() async {
        let first = PhotoItem.fixture(name: "first.jpg")
        let second = PhotoItem.fixture(name: "second.jpg")
        let editor = makeEditor(library: StubPhotoLibrary(photos: [first, second]))
        await editor.load(.fixture())

        await editor.select(first)
        editor.toggleTool(.crop)
        editor.setCropAspect(.fixed(width: 1, height: 1))

        await editor.select(second)

        #expect(editor.openTool == nil, "A crop is about one photo, so the tool closes")
        await editor.select(first)
        #expect(editor.canUndo, "And the work was not lost on the way out")
    }

    @Test("Loading another folder drops every history, because nothing is written to disk")
    func loadingAFolderDropsHistories() async {
        let editor = await editorWithCropOpen()
        editor.setCropAspect(.fixed(width: 1, height: 1))
        editor.commitCropSession()
        #expect(editor.canUndo)

        await editor.load(.fixture(name: "Other"))

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

    // MARK: - Cropping

    @Test("Opening the crop tool starts a session on the whole photo")
    func theCropToolStartsASession() async {
        let editor = await editorWithCropOpen()

        #expect(editor.isCropping)
        #expect(editor.draftCrop == .identity)
        #expect(editor.cropAspect == .original)
    }

    @Test("Picking a ratio reshapes the crop to it")
    func pickingARatioReshapesTheCrop() async {
        let editor = await editorWithCropOpen()

        editor.setCropAspect(.fixed(width: 16, height: 9))
        #expect(editor.draftCrop?.rect == CGRect(x: 0, y: 0.125, width: 1, height: 0.75))

        editor.setCropAspect(.fixed(width: 1, height: 1))
        #expect(editor.draftCrop?.rect == CGRect(x: 0.125, y: 0, width: 0.75, height: 1))
    }

    @Test("Swapping the orientation turns the shape over")
    func swappingTurnsTheShapeOver() async {
        let editor = await editorWithCropOpen()
        editor.setCropAspect(.fixed(width: 16, height: 9))

        editor.swapCropOrientation()

        #expect(editor.cropAspect == .fixed(width: 9, height: 16))
    }

    @Test("A free crop has no orientation to swap")
    func aFreeCropCannotBeSwapped() async {
        let editor = await editorWithCropOpen()
        let before = editor.draftCrop

        editor.swapCropOrientation()

        #expect(editor.draftCrop == before)
    }

    @Test("Resetting goes back to the whole photo, the right way up")
    func resettingGoesBackToThePhoto() async {
        let editor = await editorWithCropOpen()
        editor.setCropAspect(.fixed(width: 1, height: 1))
        editor.rotateCrop(clockwise: true)

        editor.resetCrop()

        #expect(editor.draftCrop == .identity)
        #expect(editor.cropAspect == .original)
    }

    @Test("Turning keeps the crop over the region it was on, and swaps the shape with the pixels")
    func turningKeepsTheRegion() async {
        let editor = await editorWithCropOpen()
        editor.setCropAspect(.fixed(width: 16, height: 9))
        // Down into a corner, so where it lands after the turn is unambiguous.
        editor.resizeCrop(moving: [.bottom, .right], to: CGPoint(x: 0.5, y: 0.25))
        let before = editor.draftCrop?.rect
        let frame = CGSize(width: 4000, height: 3000)

        editor.rotateCrop(clockwise: true)

        #expect(editor.draftCrop?.rotation == .clockwise)
        #expect(editor.cropAspect == .fixed(width: 9, height: 16), "The shape follows the pixels")

        // The point of it: the region underneath is the same region, seen
        // through a frame that has turned. Clockwise takes the top-left corner
        // to the top-right.
        let after = editor.draftCrop?.rect
        let beforePixels = CropGeometry.pixelRect(before ?? .zero, in: frame)
        let afterPixels = CropGeometry.pixelRect(after ?? .zero, in: CropGeometry.turnedSize(frame, by: .clockwise))

        #expect(afterPixels.width == beforePixels.height)
        #expect(afterPixels.height == beforePixels.width)
        #expect(afterPixels.minX == frame.height - beforePixels.maxY)
        #expect(afterPixels.minY == beforePixels.minX)
    }

    @Test("Turning back the other way returns the crop to where it was")
    func turningBackReturnsTheCrop() async {
        let editor = await editorWithCropOpen()
        editor.resizeCrop(moving: [.bottom, .right], to: CGPoint(x: 0.5, y: 0.25))
        let before = editor.draftCrop?.rect

        editor.rotateCrop(clockwise: true)
        editor.rotateCrop(clockwise: false)

        #expect(editor.draftCrop?.rotation == QuarterTurn.none)
        #expect(approximatelyEqual(editor.draftCrop?.rect, before))
    }

    @Test("A handle drag moves the crop's edge and holds the opposite one")
    func draggingAHandleMovesAnEdge() async {
        let editor = await editorWithCropOpen()
        editor.setCropAspect(.free)

        editor.resizeCrop(moving: .left, to: CGPoint(x: 0.25, y: 0))

        #expect(editor.draftCrop?.rect == CGRect(x: 0.25, y: 0, width: 0.75, height: 1))
    }

    @Test("The photo's own shape is a shape, so an edge drag scales the other axis")
    func draggingAnEdgeWithTheOriginalRatio() async {
        // What the tool opens with: `.original`, which is a 4:3 constraint rather
        // than none. Without this, a drag would look like it was ignoring the
        // ratio the panel says is selected.
        let editor = await editorWithCropOpen()

        editor.resizeCrop(moving: .left, to: CGPoint(x: 0.25, y: 0))

        #expect(editor.draftCrop?.rect == CGRect(x: 0.25, y: 0.125, width: 0.75, height: 0.75))
    }

    @Test("Dragging the middle slides the crop without resizing it")
    func draggingTheMiddleSlides() async throws {
        let editor = await editorWithCropOpen()
        editor.setCropAspect(.free)
        editor.resizeCrop(moving: [.bottom, .right], to: CGPoint(x: 0.5, y: 0.5))
        let origin = try #require(editor.draftCrop?.rect)

        editor.moveCrop(from: origin, by: CGSize(width: 0.1, height: 0.1))

        #expect(editor.draftCrop?.rect == CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5))
    }

    @Test("Where a move leaves the crop depends on the finger, not on how often it was reported")
    func movingTheCropIsIdempotent() async throws {
        // What a drag looks like from here: the same position reported over and
        // over, because `DragGesture` fires on every pointer event and a finger
        // held still still fires.
        //
        // This is the bug it guards. Applying the whole translation as a step
        // walked the crop a little further from the finger on every callback, so
        // holding it and moving it slid the crop out from under the pointer.
        let editor = await editorWithCropOpen()
        editor.setCropAspect(.free)
        editor.resizeCrop(moving: [.bottom, .right], to: CGPoint(x: 0.5, y: 0.5))
        let origin = try #require(editor.draftCrop?.rect)

        let delta = CGSize(width: 0.1, height: 0.05)
        for _ in 0..<20 {
            editor.moveCrop(from: origin, by: delta)
        }

        #expect(editor.draftCrop?.rect == CGRect(x: 0.1, y: 0.05, width: 0.5, height: 0.5))
    }

    @Test("A move is the same wherever along the drag it is asked for")
    func aMoveDoesNotDependOnTheCallbacksBeforeIt() async throws {
        let editor = await editorWithCropOpen()
        editor.setCropAspect(.free)
        editor.resizeCrop(moving: [.bottom, .right], to: CGPoint(x: 0.5, y: 0.5))
        let origin = try #require(editor.draftCrop?.rect)

        // A path — out, back near the start, then somewhere else — and then only
        // the position it ended on, which is what a drag that finished there
        // reports.
        for offset in [0.2, 0.05, -0.1, 0.0, 0.15] {
            editor.moveCrop(from: origin, by: CGSize(width: offset, height: 0))
        }

        #expect(editor.draftCrop?.rect == CGRect(x: 0.15, y: 0, width: 0.5, height: 0.5))
    }

    @Test("A drag outside a crop session changes nothing")
    func draggingOutsideASessionDoesNothing() async {
        let editor = makeEditor()
        await editor.load(.fixture())
        await editor.select(.fixture())

        editor.resizeCrop(moving: .left, to: CGPoint(x: 0.5, y: 0))
        editor.moveCrop(from: CropGeometry.unitFrame, by: CGSize(width: 0.5, height: 0.5))

        #expect(editor.draftCrop == nil)
        #expect(editor.canUndo == false)
    }

    @Test("An edge reads back as the inset the panel shows, and setting it moves the edge")
    func insetsRoundTripThroughThePanel() async {
        let editor = await editorWithCropOpen()

        // What the panel's accessible stepper does, with no pointer involved.
        editor.setCropInset(.right, to: 0.2)

        #expect(abs(editor.cropInset(.right) - 0.2) < 0.001)
        #expect(abs(editor.cropInset(.left) - 0) < 0.001)
        #expect(abs(editor.cropInset(.top) - 0.1) < 0.001, "The shape is held, so the other axis followed")
        #expect(abs(editor.cropInset(.bottom) - 0.1) < 0.001)

        editor.setCropInset(.bottom, to: 0.5)
        #expect(abs(editor.cropInset(.bottom) - 0.5) < 0.001)
        #expect(abs(editor.cropInset(.left) - 0.2) < 0.001, "And the width followed the height")
    }

    @Test("An inset is clamped, so an adjustable control cannot be driven past the frame")
    func insetsAreClamped() async throws {
        let editor = await editorWithCropOpen()

        editor.setCropInset(.left, to: 5)
        let pushed = try #require(editor.draftCrop?.rect)
        #expect(pushed.maxX <= 1.001)
        #expect(pushed.width * 4000 >= Crop.minimumPixelSize - 1, "Never narrower than the floor")

        editor.setCropInset(.left, to: -5)
        #expect(abs(editor.cropInset(.left)) < 0.001)
    }

    @Test("Dragging a handle re-renders nothing at all")
    func draggingCostsNoRender() async {
        let renderer = StubPhotoEditor()
        let editor = makeEditor(renderer: renderer)
        await editor.load(.fixture())
        await editor.select(.fixture())
        editor.toggleTool(.crop)
        let before = renderer.requestedURLs.count

        // A drag looks like this: the handler fires on every frame.
        for step in 1...20 {
            editor.resizeCrop(moving: [.right, .bottom], to: CGPoint(x: 0.9, y: 0.9 - CGFloat(step) / 100))
        }

        #expect(renderer.requestedURLs.count == before, "The overlay moves; the pixels do not")
    }

    @Test("Committing re-renders the canvas once, from the crop that was committed")
    func committingReRendersOnce() async {
        let renderer = StubPhotoEditor()
        let editor = makeEditor(renderer: renderer)
        await editor.load(.fixture())
        await editor.select(.fixture())
        editor.toggleTool(.crop)
        editor.setCropAspect(.fixed(width: 1, height: 1))
        let before = renderer.requestedURLs.count

        editor.commitCropSession()
        await editor.waitForCanvas()

        #expect(renderer.requestedURLs.count == before + 1, "One render per history move")
        #expect(renderer.renderedRecipes.last?.crop.aspect == .fixed(width: 1, height: 1))
    }

    @Test("Turning re-renders the picture the overlay sits on, because the picture itself moved")
    func turningReRendersTheBase() async {
        let renderer = StubPhotoEditor()
        let editor = makeEditor(renderer: renderer)
        await editor.load(.fixture())
        await editor.select(.fixture())
        editor.toggleTool(.crop)
        let before = renderer.requestedURLs.count

        editor.rotateCrop(clockwise: true)
        await editor.waitForCanvas()

        #expect(renderer.requestedURLs.count == before + 1)
        #expect(renderer.renderedRecipes.last?.crop.rotation == .clockwise)
        #expect(renderer.renderedRecipes.last?.crop.isIdentity == false, "Turned but not cropped")
    }

    @Test("The overlay's working picture is dropped when the tool closes")
    func theWorkingPictureIsDropped() async {
        // A turn is a whole photo's worth of pixels, so once there is one it is
        // held — and let go with the tool.
        let editor = await editorWithCropOpen()
        editor.rotateCrop(clockwise: true)
        await editor.waitForCanvas()
        #expect(editor.sessionBase != nil)

        editor.abandonCropSession()

        #expect(editor.sessionBase == nil, "Held for nothing once the tool is shut")
    }

    @Test("An unturned photo is not held twice over")
    func anUnturnedPhotoNeedsNoSeparateBase() async {
        // Nothing to turn, so nothing is held: the canvas falls back to the
        // photo's own untaken frame, which for an unturned photo is already the
        // picture the overlay wants. A second copy of it would be a whole photo's
        // worth of memory for no difference on screen.
        let editor = await editorWithCropOpen()

        #expect(editor.sessionBase == nil)
    }

    // MARK: - Helpers

    /// An editor with a photo selected and the crop tool open on it.
    private func editorWithCropOpen(
        renderer: StubPhotoEditor = StubPhotoEditor()
    ) async -> EditorViewModel {
        let editor = makeEditor(renderer: renderer)
        await editor.load(.fixture())
        await editor.select(.fixture())
        editor.toggleTool(.crop)
        return editor
    }

    private func makeEditor(
        library: StubPhotoLibrary = StubPhotoLibrary(),
        renderer: StubPhotoEditor = StubPhotoEditor()
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

/// Two rects within floating-point noise of each other.
///
/// A quarter turn is arithmetic on the corners, so turning one way and back
/// lands within about 1e-16 rather than exactly — which `==` calls different.
private func approximatelyEqual(_ lhs: CGRect?, _ rhs: CGRect?, tolerance: CGFloat = 1e-6) -> Bool {
    guard let lhs, let rhs else { return lhs == nil && rhs == nil }
    return abs(lhs.minX - rhs.minX) < tolerance
        && abs(lhs.minY - rhs.minY) < tolerance
        && abs(lhs.width - rhs.width) < tolerance
        && abs(lhs.height - rhs.height) < tolerance
}

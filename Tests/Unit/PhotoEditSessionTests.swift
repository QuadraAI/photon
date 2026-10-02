//
//  PhotoEditSessionTests.swift
//  PhotonTests
//

import CoreGraphics
import Foundation
import Testing

@testable import Photon

/// One photo's edits: what committing a session records, what Escape throws away,
/// and how undo moves through it.
@Suite("Photo edit session")
@MainActor
struct PhotoEditSessionTests {
    // MARK: - Before anything happens

    @Test("A photo with nothing done to it has nothing to undo")
    func aFreshSessionHasNothingToUndo() {
        let session = PhotoEditSession(photo: .fixture())

        #expect(session.canUndo == false)
        #expect(session.canRedo == false)
        #expect(session.undoName == nil)
        #expect(session.displayedRecipe == .identity)
        #expect(session.draft == nil)
    }

    // MARK: - The crop session

    @Test("Opening the crop tool starts from the crop the photo already has")
    func openingStartsFromTheCommittedCrop() {
        let session = committed(rect: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6), aspect: .free)

        session.beginCropSession()

        #expect(session.draft?.rect == CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6))
        #expect(session.displayedRecipe.crop.rect == session.draft?.rect, "The canvas shows the draft")
    }

    @Test("A draft is ignored when no crop session is open")
    func draftsOutsideASessionAreIgnored() {
        let session = PhotoEditSession(photo: .fixture())

        session.updateDraft(Crop(rect: CGRect(x: 0, y: 0, width: 0.5, height: 0.5), aspect: .free, rotation: .none))

        #expect(session.draft == nil)
        #expect(session.displayedRecipe == .identity)
    }

    @Test("A whole session of dragging is one step, however many handles moved")
    func aSessionRecordsOneStep() {
        let session = PhotoEditSession(photo: .fixture())
        session.beginCropSession()

        // What a drag looks like: the draft changes on every frame.
        for step in 1...50 {
            session.updateDraft(crop(offset: CGFloat(step) / 200))
        }
        session.commit()

        #expect(session.history.steps.count == 2, "One step, not fifty")
        #expect(session.currentRecipe.crop.rect.minX == crop(offset: 0.25).rect.minX)
        #expect(session.canUndo)
    }

    @Test("A session that ended where it started records nothing")
    func anUnchangedSessionRecordsNothing() {
        let session = PhotoEditSession(photo: .fixture())
        session.beginCropSession()
        session.updateDraft(crop(offset: 0.3))
        // What Reset does: back to the whole photo, which is where it started.
        session.updateDraft(.identity)

        let recorded = session.commit()

        #expect(recorded == false)
        #expect(session.history.steps.count == 1, "⌘Z is not spent on a no-op")
        #expect(session.canUndo == false)
        #expect(session.draft == nil)
    }

    @Test("Escape throws the draft away and costs nothing")
    func cancellingCostsNothing() {
        let session = PhotoEditSession(photo: .fixture())
        session.beginCropSession()
        session.updateDraft(crop(offset: 0.4))

        session.cancel()

        #expect(session.draft == nil)
        #expect(session.displayedRecipe == .identity, "The committed recipe is untouched")
        #expect(session.canUndo == false)
        #expect(session.history.steps.count == 1)
    }

    @Test("Committing twice without reopening the tool records once")
    func committingTwiceRecordsOnce() {
        let session = PhotoEditSession(photo: .fixture())
        session.beginCropSession()
        session.updateDraft(crop(offset: 0.4))
        session.commit()

        session.commit()

        #expect(session.history.steps.count == 2)
    }

    // MARK: - What a step is called

    @Test("A fixed ratio is named after the shape that was picked")
    func aRatioNamesTheStep() {
        let session = PhotoEditSession(photo: .fixture())
        session.beginCropSession()
        session.updateDraft(
            Crop(rect: CGRect(x: 0, y: 0.25, width: 1, height: 0.5), aspect: .fixed(width: 16, height: 9), rotation: .none)
        )
        session.commit()

        #expect(session.undoName == .crop(.fixed(width: 16, height: 9)))
    }

    @Test("A free drag is just a crop, and the photo's own shape is no shape at all")
    func aFreeDragIsUnnamed() {
        let free = PhotoEditSession(photo: .fixture())
        free.beginCropSession()
        free.updateDraft(Crop(rect: CGRect(x: 0.1, y: 0, width: 0.5, height: 1), aspect: .free, rotation: .none))
        free.commit()

        let original = PhotoEditSession(photo: .fixture())
        original.beginCropSession()
        original.updateDraft(Crop(rect: CGRect(x: 0, y: 0.1, width: 1, height: 0.5), aspect: .original, rotation: .none))
        original.commit()

        #expect(free.undoName == .crop(nil))
        #expect(original.undoName == .crop(nil))
    }

    @Test("A turn is named by how far it turned, even when the crop moved with it")
    func aTurnNamesTheStep() {
        let session = PhotoEditSession(photo: .fixture())
        session.beginCropSession()
        session.updateDraft(
            Crop(rect: CGRect(x: 0.1, y: 0, width: 0.8, height: 1), aspect: .original, rotation: .clockwise)
        )
        session.commit()

        #expect(session.undoName == .rotate(.clockwise))
    }

    @Test("Going back to the whole photo is a reset, however it got there")
    func resetIsNamedAsAReset() {
        // From a crop, and from a turn: both are a reset, because both end with
        // the photo the file holds.
        let fromCrop = committed(rect: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6), aspect: .free)
        fromCrop.beginCropSession()
        fromCrop.updateDraft(.identity)
        fromCrop.commit()

        let fromTurn = PhotoEditSession(photo: .fixture())
        fromTurn.beginCropSession()
        fromTurn.updateDraft(Crop(rect: CropGeometry.unitFrame, aspect: .original, rotation: .clockwise))
        fromTurn.commit()
        fromTurn.beginCropSession()
        fromTurn.updateDraft(.identity)
        fromTurn.commit()

        #expect(fromCrop.undoName == .reset)
        #expect(fromTurn.undoName == .reset)
    }

    // MARK: - The colour session

    @Test("Opening a colour change starts from the colours the photo already has")
    func colourStartsFromTheCommittedValue() {
        var committed = ColorAdjustments()
        committed.vibrance = 0.4
        let session = PhotoEditSession(photo: .fixture(), recipe: EditRecipe(crop: .identity, color: committed))

        session.beginColorSession()

        #expect(session.displayedColor == committed)
        #expect(session.colorDraft == committed)
    }

    @Test("A colour change outside a session is ignored")
    func colourOutsideASessionIsIgnored() {
        let session = PhotoEditSession(photo: .fixture())
        var adjustments = ColorAdjustments()
        adjustments.saturation = 0.5

        session.updateColorDraft(adjustments)

        #expect(session.colorDraft == nil)
        #expect(session.displayedColor == .identity)
    }

    @Test("A whole drag is one step, however many values arrived")
    func aColourDragRecordsOneStep() {
        let session = PhotoEditSession(photo: .fixture())
        session.beginColorSession()

        // What a slider drag looks like: the draft changes on every frame.
        for step in 1...50 {
            var draft = ColorAdjustments()
            draft.saturation = Double(step) / 100
            session.updateColorDraft(draft)
        }
        session.commitColor()

        #expect(session.history.steps.count == 2, "One step, not fifty")
        #expect(session.history.current.color.saturation == 0.5)
        #expect(session.canUndo)
    }

    @Test("A colour change that ended where it started records nothing")
    func anUnchangedColourChangeRecordsNothing() {
        let session = PhotoEditSession(photo: .fixture())
        session.beginColorSession()
        var adjustments = ColorAdjustments()
        adjustments.saturation = 0.3
        session.updateColorDraft(adjustments)
        // What a drag back to where it began leaves behind.
        session.updateColorDraft(.identity)

        let recorded = session.commitColor()

        #expect(recorded == false)
        #expect(session.history.steps.count == 1, "⌘Z is not spent on a no-op")
        #expect(session.colorDraft == nil)
    }

    @Test("A colour step is named after the slider that moved")
    func aColourStepIsNamedAfterItsSlider() {
        let cases: [(ColorChange, (inout ColorAdjustments) -> Void)] = [
            (.saturation, { $0.saturation = 0.4 }),
            (.vibrance, { $0.vibrance = 0.4 }),
            (.colorCast, { $0.colorCast = 0.4 }),
            (.hue, { $0[.hue, in: .yellow] = 0.4 }),
            (.bandSaturation, { $0[.saturation, in: .yellow] = 0.4 }),
            (.luminance, { $0[.luminance, in: .yellow] = 0.4 }),
        ]

        for (expected, change) in cases {
            let session = PhotoEditSession(photo: .fixture())
            session.beginColorSession()
            var adjustments = ColorAdjustments()
            change(&adjustments)
            session.updateColorDraft(adjustments)
            session.commitColor()

            #expect(session.undoName == .color(expected), "\(expected) was not named")
        }
    }

    @Test("A change that moved more than one slider is just a colour change")
    func aCompoundChangeIsNamedAsAColourChange() {
        // What Reset does, and what a change made from the keyboard can do: two
        // sliders in one step, which no single name is right for.
        let session = PhotoEditSession(photo: .fixture())
        session.beginColorSession()
        var adjustments = ColorAdjustments()
        adjustments.saturation = 0.4
        adjustments[.hue, in: .blue] = 0.2
        session.updateColorDraft(adjustments)
        session.commitColor()

        #expect(session.undoName == .color(.all))

        // And back to the photo's own colours, which is the same name.
        session.beginColorSession()
        session.updateColorDraft(.identity)
        session.commitColor()

        #expect(session.undoName == .color(.all))
    }

    @Test("Undoing while a colour change is open abandons it")
    func undoAbandonsAnOpenColourChange() {
        let session = PhotoEditSession(photo: .fixture())
        session.beginColorSession()
        var adjustments = ColorAdjustments()
        adjustments.saturation = 0.4
        session.updateColorDraft(adjustments)
        session.commitColor()

        session.beginColorSession()
        var second = ColorAdjustments()
        second.vibrance = 0.6
        session.updateColorDraft(second)

        session.undo()

        #expect(session.colorDraft == nil, "An undo leaves no draft the history has no record of")
        #expect(session.displayedColor == .identity)
    }

    @Test("A colour step is taken back to the crop it was made on")
    func aColourStepTakesBackToTheCrop() {
        // The crop is where the photo starts, rather than a step of its own.
        // `UndoManager` groups by event, and two commits made in the same turn of
        // the run loop — which is every pair a test this size makes — are one
        // group as far as it is concerned. Seeding the start keeps the test about
        // what it says it is about.
        let session = PhotoEditSession(
            photo: .fixture(),
            recipe: EditRecipe(crop: crop(offset: 0.25))
        )

        session.beginColorSession()
        var adjustments = ColorAdjustments()
        adjustments.saturation = -0.5
        session.updateColorDraft(adjustments)
        session.commitColor()

        #expect(session.history.steps.count == 2, "One step, on top of where the photo started")
        #expect(session.undoName == .color(.saturation))

        session.undo()

        #expect(session.history.current.color == .identity, "The colour goes")
        #expect(session.history.current.crop.rect.minX == 0.25, "A colour step is not a crop step")

        session.redo()
        #expect(session.history.current.color.saturation == -0.5)
    }

    // MARK: - Undo

    @Test("Undoing takes the photo back to the state before, and redoing forward again")
    func undoAndRedoMoveThePhoto() {
        let session = committed(rect: CGRect(x: 0.2, y: 0, width: 0.5, height: 1), aspect: .free)

        session.undo()
        #expect(session.currentRecipe == .identity)
        #expect(session.canRedo)
        #expect(session.redoName == .crop(nil))

        session.redo()
        #expect(session.currentRecipe.crop.rect.minX == 0.2)
        #expect(session.canUndo)
        #expect(session.canRedo == false)
    }

    @Test("Undoing at the start, and redoing at the end, do nothing")
    func undoAndRedoStopAtTheEnds() {
        let session = committed(rect: CGRect(x: 0.2, y: 0, width: 0.5, height: 1), aspect: .free)

        session.undo()
        session.undo()
        #expect(session.currentRecipe == .identity)

        session.redo()
        session.redo()
        #expect(session.currentRecipe.crop.rect.minX == 0.2)
    }

    @Test("Undo cannot drift from the history it names")
    func theMirrorTracksTheHistory() {
        let session = PhotoEditSession(photo: .fixture())

        // An interleaving that would desync a stack of paired inverses.
        for offset in [0.1, 0.2, 0.3] {
            session.beginCropSession()
            session.updateDraft(crop(offset: CGFloat(offset)))
            session.commit()
        }

        for _ in 0..<6 {
            session.undo()
            #expect(session.canUndo == session.history.canUndo)
            #expect(session.canRedo == session.history.canRedo)
        }
        #expect(session.canUndo == false)

        for _ in 0..<6 {
            session.redo()
            #expect(session.canUndo == session.history.canUndo)
            #expect(session.canRedo == session.history.canRedo)
        }
        #expect(session.canRedo == false)
        #expect(session.currentRecipe.crop.rect.minX == 0.3)
    }

    @Test("The manager and the history agree after every kind of move")
    func theManagerAndTheHistoryStayInStep() {
        let session = PhotoEditSession(photo: .fixture())

        func assertInStep(_ context: Comment) {
            #expect(session.canUndo == session.history.canUndo, context)
            #expect(session.canRedo == session.history.canRedo, context)
            #expect(session.currentRecipe == session.history.current, context)
        }

        for offset in [0.1, 0.2, 0.3] {
            session.beginCropSession()
            session.updateDraft(crop(offset: CGFloat(offset)))
            session.commit()
            assertInStep("after committing \(offset)")
        }

        // Back two, forward one, back one: the cursor takes an odd path, where a
        // manager keeping its own count would lose track of which end it is at.
        session.undo()
        session.undo()
        assertInStep("after two undos")

        session.redo()
        assertInStep("after one redo")

        session.undo()
        assertInStep("after undoing again")

        // Editing from the past, which is the move that leaves a manager holding
        // a redo the history has thrown away.
        session.beginCropSession()
        session.updateDraft(crop(offset: 0.9))
        session.commit()
        assertInStep("after editing from the past")
        #expect(session.canRedo == false, "The future the edit replaced is gone")

        session.redo()
        assertInStep("after a redo there is nothing to redo")
        #expect(session.currentRecipe.crop.rect.minX == 0.9, "The redo did not fire and undo the new edit")

        // And all the way back to the file, with the manager driving every step.
        var steps = 0
        while session.canUndo {
            session.undo()
            assertInStep("on the way back")
            steps += 1
            #expect(steps < 20, "Undo is not terminating")
        }
        #expect(session.currentRecipe == .identity, "However odd the path, the start is still reachable")
    }

    @Test("A session the window has moved on from is not kept alive by its undo manager")
    func sessionsAreNotRetainedByTheirManager() {
        // A registered undo does not hold its target, so dropping a session is
        // enough to release it: no teardown to remember, and no folder's worth of
        // histories accumulating for as long as the window is open. If this ever
        // stops being true, `EditorViewModel.scan` has to let go of them by hand.
        weak var released: PhotoEditSession?

        autoreleasepool {
            let session = PhotoEditSession(photo: .fixture())
            released = session
            session.beginCropSession()
            session.updateDraft(crop(offset: 0.3))
            session.commit()
            #expect(session.canUndo, "There is something registered to hold it")
        }

        #expect(released == nil, "The manager is holding the session it was registered against")
    }

    @Test("Undoing while a crop is open abandons it rather than leaving a state the history has no record of")
    func undoAbandonsAnOpenCrop() {
        let session = committed(rect: CGRect(x: 0.2, y: 0, width: 0.5, height: 1), aspect: .free)
        session.beginCropSession()
        session.updateDraft(crop(offset: 0.9))

        session.undo()

        #expect(session.draft == nil)
        #expect(session.displayedRecipe == .identity)
    }

    @Test("A photo handed a recipe starts from it, and that start is its first step")
    func aSessionCanStartFromARecipe() {
        let restored = EditRecipe(
            crop: Crop(rect: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5), aspect: .free, rotation: .none)
        )
        let session = PhotoEditSession(photo: .fixture(), recipe: restored)

        #expect(session.currentRecipe == restored)
        #expect(session.history.steps.count == 1, "Step one is where the photo started, whatever that was")
        #expect(session.history.steps[0].name == .original)
        #expect(session.canUndo == false)

        // And an edit on top of it is a step back to it, not to the file.
        session.beginCropSession()
        session.updateDraft(crop(offset: 0.3))
        session.commit()
        session.undo()

        #expect(session.currentRecipe == restored)
    }

    // MARK: - Helpers

    /// A session with one crop already committed.
    private func committed(rect: CGRect, aspect: AspectRatio) -> PhotoEditSession {
        let session = PhotoEditSession(photo: .fixture())
        session.beginCropSession()
        session.updateDraft(Crop(rect: rect, aspect: aspect, rotation: .none))
        session.commit()
        return session
    }

    /// A crop that differs from the identity, so a step's position in the list
    /// can be seen in what it produced.
    private func crop(offset: CGFloat) -> Crop {
        Crop(rect: CGRect(x: offset, y: 0, width: 1 - offset, height: 1), aspect: .free, rotation: .none)
    }
}

// A session's own value, which the tests above assert against by name.
private extension PhotoEditSession {
    var currentRecipe: EditRecipe { history.current }
}

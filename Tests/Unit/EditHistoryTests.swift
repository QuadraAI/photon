//
//  EditHistoryTests.swift
//  PhotonTests
//

import CoreGraphics
import Foundation
import Testing

@testable import Photon

/// The history: a list of recipes and a cursor, with undo as a state restore
/// rather than a replay of an inverse.
@Suite("Edit history")
struct EditHistoryTests {
    // MARK: - Recording

    @Test("A photo nothing has been done to has one step, and it is the original")
    func startsAtTheOriginal() {
        let history = EditHistory()

        #expect(history.steps.count == 1)
        #expect(history.steps[0].name == .original)
        #expect(history.current == .identity)
        #expect(history.cursor == 0)
        #expect(history.canUndo == false)
        #expect(history.canRedo == false)
        #expect(history.undoName == nil)
        #expect(history.redoName == nil)
    }

    @Test("Recording appends a step and leaves the photo on it")
    func recordingAppends() {
        var history = EditHistory()

        history.record(recipe(0.2), name: .crop(nil))

        #expect(history.steps.count == 2)
        #expect(history.cursor == 1)
        #expect(history.current == recipe(0.2))
        #expect(history.canUndo)
        #expect(history.canRedo == false)
        #expect(history.undoName == .crop(nil))
    }

    @Test("Steps carry a stable identity, so a list of them can keep its place")
    func stepsKeepTheirIdentity() {
        var history = EditHistory()
        history.record(recipe(0.2), name: .crop(nil))
        let id = history.steps[1].id

        history.undo()
        history.redo()

        #expect(history.steps[1].id == id)
    }

    // MARK: - Moving

    @Test("Undoing returns to the state before, and redoing returns to the one after")
    func undoRestoresTheEarlierState() {
        var history = EditHistory()
        history.record(recipe(0.2), name: .crop(nil))
        history.record(recipe(0.4), name: .crop(nil))

        history.undo()
        #expect(history.current == recipe(0.2))
        #expect(history.canUndo)
        #expect(history.canRedo)
        #expect(history.redoName == .crop(nil))

        history.redo()
        #expect(history.current == recipe(0.4))
        #expect(history.canRedo == false)
    }

    @Test("Undoing and redoing stop at the ends rather than running off them")
    func movingStopsAtTheEnds() {
        var history = EditHistory()
        history.record(recipe(0.2), name: .crop(nil))

        history.undo()
        history.undo()
        #expect(history.cursor == 0)
        #expect(history.current == .identity, "Still the original photo")

        history.redo()
        history.redo()
        #expect(history.cursor == 1)
    }

    @Test("Undoing all the way back is how a photo is reset")
    func undoingToTheStartIsTheOriginal() {
        var history = EditHistory()
        history.record(recipe(0.2), name: .crop(nil))
        history.record(recipe(0.4), name: .rotate(.clockwise))

        history.undo()
        history.undo()

        #expect(history.current == .identity)
        #expect(history.steps[0].name == .original)
    }

    // MARK: - Editing from the past

    @Test("Recording after an undo discards what followed it")
    func recordingTruncatesTheFuture() {
        var history = EditHistory()
        history.record(recipe(0.2), name: .crop(nil))
        history.record(recipe(0.4), name: .crop(nil))
        history.undo()

        history.record(recipe(0.6), name: .rotate(.clockwise))

        #expect(history.steps.count == 3, "The step that was redone to is gone")
        #expect(history.current == recipe(0.6))
        #expect(history.canRedo == false)
        #expect(history.redoName == nil)
    }

    // MARK: - The bound

    @Test("The history is bounded, and the original survives the bound")
    func trimmingKeepsTheOriginal() {
        var history = EditHistory()

        for step in 1...(EditHistory.limit + 10) {
            history.record(recipe(CGFloat(step) / 100), name: .crop(nil))
        }

        #expect(history.steps.count == EditHistory.limit + 1)
        #expect(history.steps.first?.name == .original, "However long the session, ⌘Z can always reach the start")
        #expect(history.current == recipe(CGFloat(EditHistory.limit + 10) / 100))
        #expect(history.cursor == EditHistory.limit)
    }

    @Test("Trimming takes the cursor with it, so the photo does not change")
    func trimmingKeepsThePhotoWhereItIs() {
        var history = EditHistory()

        for step in 1...(EditHistory.limit + 10) {
            history.record(recipe(CGFloat(step) / 100), name: .crop(nil))
        }
        let current = history.current

        history.undo()

        #expect(history.current == recipe(CGFloat(EditHistory.limit + 9) / 100))
        #expect(history.current != current)
        #expect(history.cursor == EditHistory.limit - 1)
    }

    @Test("Undoing to the very start still reaches the original after trimming")
    func undoingPastATrimLandsOnTheOriginal() {
        var history = EditHistory()

        for step in 1...(EditHistory.limit + 10) {
            history.record(recipe(CGFloat(step) / 100), name: .crop(nil))
        }
        while history.canUndo { history.undo() }

        #expect(history.current == .identity)
        #expect(history.canUndo == false)
    }

    // MARK: - Persistence

    @Test("A history survives a round trip through JSON")
    func historyIsCodable() throws {
        var history = EditHistory()
        history.record(recipe(0.2), name: .crop(.fixed(width: 16, height: 9)))
        history.record(recipe(0.4), name: .rotate(.clockwise))
        history.undo()

        let data = try JSONEncoder().encode(history)
        let decoded = try JSONDecoder().decode(EditHistory.self, from: data)

        #expect(decoded == history)
        #expect(decoded.current == history.current)
        #expect(decoded.cursor == history.cursor)
    }

    // MARK: - Helpers

    /// A recipe that differs from the identity, so a step's position in the list
    /// can be seen in what it produced.
    private func recipe(_ offset: CGFloat) -> EditRecipe {
        EditRecipe(
            crop: Crop(
                rect: CGRect(x: offset, y: 0, width: 0.5, height: 1),
                aspect: .free,
                rotation: .none
            )
        )
    }
}

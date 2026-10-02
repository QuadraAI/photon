//
//  PhotoEditSession.swift
//  Photon
//

import Foundation
import Observation

/// One photo's edits, for as long as the window that opened it is around.
///
/// A session per photo rather than one history per window: undo that outlived the
/// photo it was recorded against would let ⌘Z in one picture take back an edit to
/// another, which is what happens the first time a user crops one photo, clicks
/// the next, and crops that.
///
/// ``EditHistory`` is the whole of the state — every step taken, and where in them
/// the photo is. Undo moves that cursor, and ``undoManager`` is only the surface
/// macOS drives. It is told what to do and never asked: a manager consulted about
/// what can be undone is a second opinion about it, and an earlier version that
/// took one reported a redo the history had no step left to name.
@Observable
@MainActor
final class PhotoEditSession {
    let photo: PhotoItem

    /// Every step taken on this photo, and where in them it currently is.
    private(set) var history: EditHistory

    /// The crop being worked on while the crop tool is open, and nil otherwise.
    ///
    /// Held apart from ``history`` so a session can be abandoned — Escape, or
    /// closing the tool — without leaving anything behind. Nothing is recorded
    /// until it is committed, so a drag costs no history and a session that ended
    /// where it started costs no step.
    private(set) var draft: Crop?

    /// What undoing and redoing would do, mirrored from ``history`` so the toolbar
    /// and the Edit menu have something observable to react to.
    private(set) var canUndo = false
    private(set) var canRedo = false
    private(set) var undoName: EditStepName?
    private(set) var redoName: EditStepName?

    /// Does not hold this session, which is why dropping one is enough — see
    /// `sessionsAreNotRetainedByTheirManager`.
    @ObservationIgnored private let undoManager = UndoManager()

    init(photo: PhotoItem, recipe: EditRecipe = .identity) {
        self.photo = photo
        self.history = EditHistory(recipe: recipe)
        refresh()
    }

    // MARK: - Reading

    /// What the canvas should be showing: the draft while the crop tool is open,
    /// the committed recipe otherwise.
    var displayedRecipe: EditRecipe {
        EditRecipe(crop: draft ?? history.current.crop)
    }

    // MARK: - Cropping

    /// Opens the crop tool, starting from the crop the photo already has.
    func beginCropSession() {
        draft = history.current.crop
    }

    func updateDraft(_ crop: Crop) {
        guard draft != nil else { return }
        draft = crop
    }

    /// Records the draft as a single step, named after what it changed.
    ///
    /// One step per session however many handles were dragged: a step per drag
    /// would bury the history under a few seconds of fiddling, and the whole
    /// point of a history is being able to find your way back through it.
    ///
    /// - Returns: Whether anything was recorded. A session that ended where it
    ///   started leaves nothing behind, so ⌘Z is not spent on a no-op.
    @discardableResult
    func commit() -> Bool {
        guard let draft else { return false }
        self.draft = nil

        let base = history.current.crop
        guard draft != base else { return false }

        history.record(EditRecipe(crop: draft), name: Self.name(from: base, to: draft))
        registerUndo()
        refresh()
        return true
    }

    /// Throws the draft away. The committed recipe is untouched and no step is
    /// recorded — Escape has to be able to cost nothing.
    func cancel() {
        draft = nil
    }

    // MARK: - Undo

    /// Takes the photo back a step.
    ///
    /// The step that is left behind stays in the history rather than being
    /// discarded, which is what redo is: the list of what the photo has been
    /// through does not change when the cursor moves over it.
    ///
    /// Guarded by the history rather than by the manager, so the two can never
    /// disagree about whether there is anything to take back — the manager is
    /// asked to perform a step, never whether one exists.
    func undo() {
        guard history.canUndo else { return }
        undoManager.undo()
    }

    func redo() {
        guard history.canRedo else { return }
        undoManager.redo()
    }

    // MARK: - Internals

    /// Registers the step undoing runs, and the one redoing runs.
    ///
    /// Two registrations rather than a snapshot and its inverse: each moves the
    /// cursor one step, so the pair stays right however many times it is used.
    ///
    /// The handler is `@MainActor` in the SDK, which is what lets it touch this
    /// session directly. The registration inside it lands on the *opposite* stack
    /// — that is what `UndoManager` does with anything registered while it is
    /// undoing or redoing — which is what makes one pair undo and redo
    /// indefinitely without either stack being maintained by hand.
    private func registerUndo() {
        undoManager.registerUndo(withTarget: self) { session in
            session.stepBack()
            session.registerRedo()
        }
    }

    private func registerRedo() {
        undoManager.registerUndo(withTarget: self) { session in
            session.stepForward()
            session.registerUndo()
        }
    }

    /// Moves the cursor back, leaving the draft behind.
    ///
    /// The draft goes because an undo moves the photo to a state that was
    /// recorded before it existed, so keeping it would leave the canvas showing a
    /// crop the history has no record of. Lightroom does the same: ⌘Z in crop
    /// mode steps the history and leaves the tool.
    private func stepBack() {
        history.undo()
        draft = nil
        refresh()
    }

    private func stepForward() {
        history.redo()
        draft = nil
        refresh()
    }

    /// Names a session by what it did, in the order a photographer would say it.
    ///
    /// One step, so one name. Going back to the whole photo is a reset however it
    /// got there; otherwise a turn is what the session was about even when the
    /// crop moved with it, and the ratio earns a mention only when it is one the
    /// user picked — a free drag, and the photo's own shape, are just "Crop".
    private static func name(from base: Crop, to crop: Crop) -> EditStepName {
        if crop.isIdentity { return .reset }

        let turned = QuarterTurn(rawValue: (crop.rotation.rawValue - base.rotation.rawValue + 4) % 4) ?? .none
        if turned != .none { return .rotate(turned) }

        if case .fixed = crop.aspect { return .crop(crop.aspect) }
        return .crop(nil)
    }

    /// Reads the four mirrors off the history, which is the only thing that knows.
    private func refresh() {
        canUndo = history.canUndo
        canRedo = history.canRedo
        undoName = history.undoName
        redoName = history.redoName
    }
}

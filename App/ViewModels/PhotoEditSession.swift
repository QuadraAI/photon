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

    /// The tool that is open on this photo, and what it is working on.
    ///
    /// One value, and at most one tool: a crop being dragged and a grade being
    /// dragged are not two sessions that have to agree, they are two cases of one
    /// value that cannot both be true. Nothing is recorded until the tool is let
    /// go, so a drag costs no history and a session that ended where it started
    /// costs no step.
    private(set) var tool: ToolSession = .none

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

    /// What the canvas should be showing: the draft while its tool is open, the
    /// committed recipe otherwise.
    ///
    /// A delta on the committed recipe, like every other write — the open tool's
    /// field replaced through the key path its tool owns. Building the recipe from
    /// the fields named here instead would quietly drop the field of a tool added
    /// later, which is the same mistake as a commit that builds a fresh recipe.
    var displayedRecipe: EditRecipe {
        switch tool {
        case .none:
            history.current
        case .crop(let crop):
            CropTool.commit(crop, into: history.current)
        case .colour(let colour):
            ColorTool.commit(colour, into: history.current)
        }
    }

    /// The colours the panel is showing: the drag in progress, or what the photo
    /// has been committed to.
    var displayedColor: ColorAdjustments { displayedRecipe.color }

    /// The crop being worked on, or nil when the crop tool is not the one open.
    ///
    /// What the overlay draws and the panel edits, read off the one value that
    /// knows.
    var draft: Crop? { tool.draftCrop }

    // MARK: - The open tool

    /// Opens `tool` on this photo, starting from what the photo is committed to.
    ///
    /// Whatever was open is recorded first, because switching tools is one of the
    /// ways out of a tool and the rule is the same for all of them: record, then
    /// open. Leaving it to the caller to remember is how a crop came to be dropped
    /// by a slider touched in the moment between one panel closing and the picture
    /// it recorded arriving.
    ///
    /// A tool that is already open is left where it is rather than restarted: a
    /// drag that begins on one slider and ends on another is still one step, and
    /// so is a crop handle taken up again.
    func open(_ tool: Tool) {
        guard self.tool.tool != tool else { return }
        record()

        switch tool {
        case .crop:
            self.tool = .crop(history.current.crop)
        case .color:
            self.tool = .colour(history.current.color)
        case .light, .presets:
            // Panels that are still placeholders: nothing to work on yet.
            self.tool = .none
        }
    }

    /// Changes the crop being worked on, in place, and does nothing when the crop
    /// tool is not the one open.
    ///
    /// A copy with the fields that changed set on it, rather than a fresh `Crop`
    /// built from the ones that did not: a field added later cannot be quietly
    /// dropped by a call site that never heard of it.
    func changeCrop(_ change: (inout Crop) -> Void) {
        guard case .crop(var crop) = tool else { return }
        change(&crop)
        tool = .crop(crop)
    }

    /// Changes the colours being worked on, in place, and does nothing when the
    /// colour tool is not the one open.
    func changeColour(_ change: (inout ColorAdjustments) -> Void) {
        guard case .colour(var colour) = tool else { return }
        change(&colour)
        tool = .colour(colour)
    }

    /// Lets the tool go without recording anything: Escape and Cancel have to be
    /// able to cost nothing.
    func discard() {
        tool = .none
    }

    // MARK: - Recording what a tool did

    /// Records whatever tool is open, as a single step, and lets it go.
    ///
    /// - Returns: Whether anything was recorded.
    @discardableResult
    func record() -> Bool {
        switch tool {
        case .none: false
        case .crop: recordCrop()
        case .colour: recordColour()
        }
    }

    /// Records the crop being worked on as a single step, and lets the tool go.
    ///
    /// One step per session however many handles were dragged: a step per drag
    /// would bury the history under a few seconds of fiddling, and the whole
    /// point of a history is being able to find your way back through it.
    ///
    /// - Returns: Whether anything was recorded. A session that ended where it
    ///   started leaves nothing behind, so ⌘Z is not spent on a no-op.
    @discardableResult
    func recordCrop() -> Bool {
        guard case .crop(let crop) = tool else { return false }
        tool = .none

        let base = history.current
        // The colour is carried over rather than defaulted: the tool writes its
        // own field of the recipe and every other one comes from what the photo
        // already is. Building a fresh `EditRecipe` here silently threw the grade
        // away, and the rule is what stops the next tool doing the same to the crop.
        return record(
            CropTool.commit(crop, into: base),
            unlessItIs: base,
            named: Self.name(from: base.crop, to: crop)
        )
    }

    /// Records the colours being worked on as a single step, and lets the tool go.
    ///
    /// - Returns: Whether anything was recorded. A drag that came back to where it
    ///   started leaves nothing behind, so ⌘Z is not spent on a no-op.
    @discardableResult
    func recordColour() -> Bool {
        guard case .colour(let colour) = tool else { return false }
        tool = .none

        let base = history.current
        return record(
            ColorTool.commit(colour, into: base),
            unlessItIs: base,
            named: Self.name(from: base.color, to: colour)
        )
    }

    /// Appends `recipe` as a step, unless the photo is already it.
    ///
    /// - Returns: Whether anything was recorded.
    private func record(_ recipe: EditRecipe, unlessItIs base: EditRecipe, named name: EditStepName) -> Bool {
        guard recipe != base else { return false }

        history.record(recipe, name: name)
        registerUndo()
        refresh()
        return true
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

    /// Moves the cursor back, leaving the drafts behind.
    ///
    /// The drafts go because an undo moves the photo to a state that was recorded
    /// before they existed, so keeping them would leave the canvas showing a crop,
    /// or a grade, the history has no record of. Lightroom does the same: ⌘Z in
    /// crop mode steps the history and leaves the tool.
    private func stepBack() {
        history.undo()
        discard()
        refresh()
    }

    private func stepForward() {
        history.redo()
        discard()
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

    /// Names a colour change by the slider that was moved.
    ///
    /// A drag moves one slider, so this is usually exact. It is not always:
    /// Reset moves all of them, and a change made from the keyboard can be
    /// followed by another before either is committed. Those are just "Color",
    /// which is true and does not guess at which of them the user would call it.
    private static func name(from base: ColorAdjustments, to color: ColorAdjustments) -> EditStepName {
        func bandsMoved(_ channel: HSLChannel) -> Bool {
            ColorBand.allCases.contains { color[channel, in: $0] != base[channel, in: $0] }
        }

        // Every slider, and whether this change moved it.
        let moved = [
            (ColorChange.saturation, color.saturation != base.saturation),
            (.vibrance, color.vibrance != base.vibrance),
            (.colorCast, color.colorCast != base.colorCast),
            (.hue, bandsMoved(.hue)),
            (.bandSaturation, bandsMoved(.saturation)),
            (.luminance, bandsMoved(.luminance)),
        ].filter(\.1).map(\.0)

        guard let only = moved.first, moved.count == 1 else { return .color(.all) }
        return .color(only)
    }

    /// Reads the four mirrors off the history, which is the only thing that knows.
    private func refresh() {
        canUndo = history.canUndo
        canRedo = history.canRedo
        undoName = history.undoName
        redoName = history.redoName
    }
}

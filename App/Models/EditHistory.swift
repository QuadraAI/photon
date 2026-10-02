//
//  EditHistory.swift
//  Photon
//

import Foundation

/// What a history step did, in the user's terms.
///
/// An enum rather than a stored string: the history is a value that gets compared
/// and serialised, and a localized string in it would freeze the language it was
/// recorded in. ``EditStepName+Presentation`` turns these into words.
nonisolated enum EditStepName: Equatable, Sendable, Codable {
    /// The photo as the file holds it. Always the first step.
    case original
    /// Cropping, held to `aspect` — nil when the user dragged free.
    case crop(AspectRatio?)
    /// Turning, by however much the session turned it.
    case rotate(QuarterTurn)
    /// Back to the whole photo.
    case reset
}

/// One point in a photo's editing history.
nonisolated struct EditStep: Identifiable, Equatable, Sendable, Codable {
    /// Stable across undo and redo, so a list of steps can keep its identity —
    /// and its scroll position — while the cursor moves over it.
    let id: UUID

    let name: EditStepName

    /// The photo's whole look at this point, not a change to the last one.
    let recipe: EditRecipe

    let date: Date

    init(id: UUID = UUID(), name: EditStepName, recipe: EditRecipe, date: Date = .now) {
        self.id = id
        self.name = name
        self.recipe = recipe
        self.date = date
    }
}

/// Everything a photo has been through, and where in it we are.
///
/// A list of recipes with a cursor, rather than a list of paired apply/revert
/// closures. Undo then *restores a state* instead of replaying an inverse, which
/// is what makes it impossible for ⌘Z to disagree with what the user sees — and
/// what makes jumping to any step, listing them, or saving them all the same
/// small addition later on.
nonisolated struct EditHistory: Equatable, Sendable, Codable {
    /// Every step taken, oldest first. The first is always the file's own photo,
    /// which is what the user resets to and what is never dropped.
    private(set) var steps: [EditStep]

    /// Which step the photo is on. Always a valid index into ``steps``.
    private(set) var cursor: Int

    /// How many steps are kept beyond the first.
    ///
    /// A bound rather than none: a session of fiddling can record hundreds, and
    /// recipes are tiny but not free. Fifty is far more than anyone steps back
    /// through by hand.
    static let limit = 50

    /// A history holding nothing but `recipe` as its original step.
    init(recipe: EditRecipe = .identity) {
        steps = [EditStep(name: .original, recipe: recipe)]
        cursor = 0
    }

    /// The photo's current look.
    var current: EditRecipe { steps[cursor].recipe }

    var canUndo: Bool { cursor > 0 }
    var canRedo: Bool { cursor < steps.count - 1 }

    /// The step the photo is on, which is what undoing takes back.
    var currentStep: EditStep { steps[cursor] }

    /// The step undoing would return to, or nil at the start.
    var undoName: EditStepName? { canUndo ? steps[cursor].name : nil }

    /// The step redoing would go forward to, or nil at the end.
    var redoName: EditStepName? { canRedo ? steps[cursor + 1].name : nil }

    /// Records `recipe` as a step named `name`.
    ///
    /// Anything after the cursor is dropped first: editing from a point in the
    /// past makes the future that followed it unreachable, which is what every
    /// editor does and what "redo" would otherwise have to lie about.
    mutating func record(_ recipe: EditRecipe, name: EditStepName, at date: Date = .now) {
        steps.removeSubrange((cursor + 1)...)
        steps.append(EditStep(name: name, recipe: recipe, date: date))
        cursor = steps.count - 1
        trim()
    }

    mutating func undo() {
        guard canUndo else { return }
        cursor -= 1
    }

    mutating func redo() {
        guard canRedo else { return }
        cursor += 1
    }

    /// Drops the oldest steps once there are more than ``limit`` beyond the
    /// first, and takes the cursor with them.
    ///
    /// From just after the first step, deliberately: the bound is on how much
    /// fiddling is remembered, not on being able to get back to the photo the
    /// file holds.
    private mutating func trim() {
        let overflow = steps.count - (Self.limit + 1)
        guard overflow > 0 else { return }
        steps.removeSubrange(1...overflow)
        cursor = max(0, cursor - overflow)
    }
}

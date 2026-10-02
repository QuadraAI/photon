//
//  EditTool.swift
//  Photon
//

import CoreGraphics
import CoreImage
import Foundation

/// A stage of the editing pipeline.
///
/// The declaration order **is** the order the stages run in, and an enum rather
/// than a list because that order is a specification rather than a preference: a
/// tonal stage that ran on a cropped picture would measure the crop rather than
/// the photo, and two crops of the same picture would come out differently graded.
/// It is why Lightroom ships a process version rather than a reorderable stack.
///
/// Reordering is deliberately not a feature. A new stage is a new case at the
/// point it belongs, which is a change to the pipeline and not to a tool.
nonisolated enum PipelineStage: CaseIterable {
    /// The colour tool's work, on the whole photo.
    case colour

    /// The frame: turned first, then the crop taken out of it.
    ///
    /// One stage rather than two, because the turn is not a step the crop is
    /// applied after — the rect is normalized to the frame *after* the turn — and
    /// because both belong to the one tool that owns the value.
    case geometry
}

/// What a stage may reach for besides the picture.
///
/// Deliberately the only extension point a tool gets. Masking and denoise will
/// need more than the image — a mask, a model — and they arrive here rather than
/// as another parameter every tool has to carry.
///
/// It carries the engine and never the recipe: a tool sees its own value and the
/// picture, and nothing of what any other tool was told.
nonisolated struct EditContext: Sendable {
    /// The context the previews are staged with, for a tool that has to render
    /// something of its own.
    let imageContext: CIContext

    /// The band maths, compiled once by the engine and handed to the stage that
    /// needs it: a second compile costs a second Metal library.
    ///
    /// Nil on a machine with no Metal device, where the three global sliders still
    /// work and the bands go quiet.
    let colorKernel: CIColorKernel?

    /// The photo being edited, for a tool that has to measure the picture rather
    /// than transform it.
    let url: URL

    /// The photo's own pixel size, upright.
    ///
    /// Geometry is measured in this rather than in the preview's size: turning a
    /// normalized rect into pixels at preview size would give a different crop on
    /// export than the one the user dragged.
    let sourceSize: CGSize

    /// How far each channel has to move to take a photo's own cast out, or nil
    /// when it cannot be measured.
    ///
    /// Asynchronous because measuring is a decode of its own, and the engine is an
    /// actor: the ask crosses into it. It remembers the measurement, because a
    /// slider drag asks on every frame.
    let castGains: @Sendable (URL) async -> SIMD3<Double>?
}

/// A tool: one field of the recipe, and what applying that field does to a photo.
///
/// Tools are behaviour and not wire format — a recipe is `Codable` and stays
/// readable whether or not the tool that wrote it still exists. What a tool adds
/// is where its field sits in the pipeline, and how a commit writes it.
nonisolated protocol EditTool {
    /// What the tool writes.
    ///
    /// `Equatable`, because a recipe is: comparing two of them is how the canvas
    /// knows whether the picture it is showing is the one being asked for, and how
    /// a commit knows it has nothing to record.
    associatedtype Value: Equatable

    /// The field of the recipe the tool owns.
    ///
    /// A key path rather than an assignment written out where the commit happens,
    /// so that a commit can only ever write its own field — every other field
    /// comes from the recipe the photo is already on. That is the rule that was
    /// broken when committing a crop built a fresh recipe and defaulted the grade
    /// away.
    static var own: WritableKeyPath<EditRecipe, Value> { get }

    /// Where in the pipeline this tool's work happens.
    static var stage: PipelineStage { get }

    /// A value of this tool's own: something it can be told to do.
    ///
    /// The pipeline's invariant test commits this against a recipe with every
    /// other field set, and holds that only this tool's field moved. It comes from
    /// the tool because a tool is the only thing that knows what its own value
    /// means, and because a list of them in the test would be a list a new tool is
    /// not on — which is the test not covering the tool that has just landed.
    static var sample: Value { get }

    /// The photo with this tool's value applied to it.
    ///
    /// Asynchronous because a stage may have to ask the engine for something — the
    /// colour tool measures the photo before it can correct it — and because the
    /// tools still to come will: a mask is a decode and a model is an inference.
    static func apply(_ value: Value, to image: CIImage, context: EditContext) async -> CIImage
}

/// A tool, with its own value type set aside.
///
/// What the pipeline walks and what the invariant test walks: neither has to know
/// any tool by name, and a tool that is registered is in both.
nonisolated struct RegisteredTool: Sendable {
    /// What the tool is called, for a failure message.
    let name: String

    /// Where in the pipeline it runs.
    let stage: PipelineStage

    /// The recipe with this tool's work in it, as a delta on the recipe given.
    let commit: @Sendable (EditRecipe) -> EditRecipe

    /// Whether two recipes ask the same of this tool.
    let isUnchanged: @Sendable (EditRecipe, EditRecipe) -> Bool

    /// The photo with this tool's field of the recipe applied to it.
    let apply: @Sendable (EditRecipe, CIImage, EditContext) async -> CIImage
}

nonisolated extension EditTool {
    /// This tool, with its value type set aside so the registry can hold it.
    static var registered: RegisteredTool {
        RegisteredTool(
            name: String(describing: Self.self),
            stage: stage,
            commit: { committed(into: $0) },
            isUnchanged: { isUnchanged(from: $0, to: $1) },
            apply: { await applying($0, to: $1, context: $2) }
        )
    }

    /// The recipe with this tool's work in it, as a delta on `recipe`.
    ///
    /// A delta rather than a fresh recipe: every field the tool does not own comes
    /// from what the photo already is.
    static func commit(_ value: Value, into recipe: EditRecipe) -> EditRecipe {
        var recipe = recipe
        recipe[keyPath: own] = value
        return recipe
    }

    /// ``commit(_:into:)`` with the tool's own sample value, which is what the
    /// invariant test walks.
    static func committed(into recipe: EditRecipe) -> EditRecipe {
        commit(sample, into: recipe)
    }

    /// Whether two recipes ask the same of this tool.
    ///
    /// How the invariant test asks a tool whether its field survived another
    /// tool's commit without knowing what its field is.
    static func isUnchanged(from before: EditRecipe, to after: EditRecipe) -> Bool {
        before[keyPath: own] == after[keyPath: own]
    }

    /// The photo with this tool's field of `recipe` applied to it.
    static func applying(_ recipe: EditRecipe, to image: CIImage, context: EditContext) async -> CIImage {
        await apply(recipe[keyPath: own], to: image, context: context)
    }
}

/// Every tool the editor has.
///
/// The pipeline walks this and the invariant test walks this, so a tool that is
/// registered here is in both the day it lands — and a tool that is not is in
/// neither. Tools at one stage run in the order they are listed.
nonisolated enum EditTools {
    static var all: [RegisteredTool] {
        [ColorTool.registered, CropTool.registered]
    }
}

//
//  CropTool.swift
//  Photon
//

import CoreGraphics
import CoreImage

/// Where the photo is cut, and how it is turned before it is cut.
///
/// The last stage of the pipeline: a crop is what is left of the frame, so
/// everything that measures the photo — the colour tool most of all — has to have
/// run before it.
///
/// What the tool owns is ``EditRecipe/crop``, which holds the turn as well as the
/// rect: a quarter turn is not a step the crop is applied after, it is the frame
/// the rect is measured in.
nonisolated enum CropTool: EditTool {
    static var own: WritableKeyPath<EditRecipe, Crop> { \.crop }

    static let stage: PipelineStage = .geometry

    /// A crop of the middle half of the photo, held to nothing: a value that is
    /// not the photo's own, which is what the invariant test needs.
    static let sample = Crop(
        rect: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
        aspect: .free,
        rotation: .none
    )

    /// The photo turned and then cut.
    ///
    /// `oriented(_:)` rather than a transform for the turn: it re-derives the
    /// extent, where a rotation of a quarter turn about the origin leaves the
    /// picture sitting outside its own bounds.
    static func apply(_ crop: Crop, to image: CIImage, context: EditContext) async -> CIImage {
        var image = image
        if crop.rotation != .none {
            image = image.oriented(crop.rotation.orientation)
        }

        let frame = CropGeometry.turnedSize(context.sourceSize, by: crop.rotation)
        let rect = CropGeometry.coreImageRect(crop.rect, frame: frame, extent: image.extent).integral

        let cropped = image.cropped(to: rect)
        // `cropped(to:)` keeps the crop where it was in the parent, so what is
        // left is the same size as the photo with everything outside the rect
        // transparent. Moving it back to the origin is what makes the render the
        // size of the crop.
        return cropped.transformed(
            by: CGAffineTransform(translationX: -cropped.extent.minX, y: -cropped.extent.minY)
        )
    }
}

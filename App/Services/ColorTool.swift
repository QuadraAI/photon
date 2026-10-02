//
//  ColorTool.swift
//  Photon
//

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// The photo's colour: the cast, the two global sliders, and the eight bands.
///
/// The first stage of the pipeline, and the whole photo's: a tonal stage that ran
/// on a cropped image would measure the crop rather than the photo, and two crops
/// of the same picture would come out differently graded.
///
/// Within the stage the order is the panel's, top to bottom: a cast is taken out
/// of the photo before anything is measured against it, the two global sliders act
/// on every colour, and the eight bands act last, on the colours the user can see
/// by then. Every step is skipped when it is not asked for, so a photo with only a
/// cast correction never pays for the kernel, and one with only a band shift never
/// pays for the measurement.
nonisolated enum ColorTool: EditTool {
    static var own: WritableKeyPath<EditRecipe, ColorAdjustments> { \.color }

    static let stage: PipelineStage = .colour

    /// Half again as much colour as the file has, which is a change the invariant
    /// test can see.
    static var sample: ColorAdjustments {
        var colour = ColorAdjustments()
        colour.saturation = 0.5
        return colour
    }

    /// How far a channel may be pushed to take a cast out.
    ///
    /// A photo that is one colour throughout — a frame filled by a leaf — would
    /// otherwise ask for an unbounded correction.
    static let castGainRange: ClosedRange<Double> = 0.5...2

    /// The photo with the colour tool's work on it.
    static func apply(_ color: ColorAdjustments, to image: CIImage, context: EditContext) async -> CIImage {
        var image = image

        if color.colorCast > 0, let gains = await context.castGains(context.url) {
            image = balanced(image, by: gains, amount: color.colorCast)
        }

        if color.vibrance != 0 {
            let vibrance = CIFilter.vibrance()
            vibrance.inputImage = image
            vibrance.amount = Float(color.vibrance)
            image = vibrance.outputImage ?? image
        }

        if color.saturation != 0 {
            let controls = CIFilter.colorControls()
            controls.inputImage = image
            // −1 is grey and +1 is twice the colour, which is what a saturation
            // slider is expected to do at its ends.
            controls.saturation = Float(1 + color.saturation)
            image = controls.outputImage ?? image
        }

        if color.hasBandShift, let colorKernel = context.colorKernel,
           let banded = ColorKernel.apply(color, to: image, using: colorKernel) {
            image = banded
        }

        return image
    }

    /// The photo with each channel moved `amount` of the way to its gain.
    ///
    /// Applied in the working space, which is linear: a white balance multiplies
    /// light. The same multiplication on gamma-encoded values would correct by a
    /// different amount in the shadows than in the highlights.
    private static func balanced(_ image: CIImage, by gains: SIMD3<Double>, amount: Double) -> CIImage {
        func scaled(_ gain: Double) -> CGFloat { CGFloat(1 + amount * (gain - 1)) }

        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = image
        matrix.rVector = CIVector(x: scaled(gains.x), y: 0, z: 0, w: 0)
        matrix.gVector = CIVector(x: 0, y: scaled(gains.y), z: 0, w: 0)
        matrix.bVector = CIVector(x: 0, y: 0, z: scaled(gains.z), w: 0)
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        matrix.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        return matrix.outputImage ?? image
    }
}

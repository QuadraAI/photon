//
//  EditRecipeTests.swift
//  PhotonTests
//

import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import Photon

/// The recipe: what a photo currently is, as a value that can be compared,
/// stored and handed back to the engine.
@Suite("Edit recipe")
struct EditRecipeTests {
    // MARK: - Identity

    @Test("The identity recipe asks for the photo exactly as the file holds it")
    func identityIsTheWholePhoto() {
        #expect(EditRecipe.identity.isIdentity)
        #expect(Crop.identity.isIdentity)
        #expect(Crop.identity.rotation == .none)
        #expect(Crop.identity.aspect == .original)
    }

    @Test("A crop the solver arrived at is still the whole photo")
    func solverRoundingIsStillIdentity() {
        // What `fitted(_:inside:frame:)` produces when the frame is already the
        // right shape: the full frame, through arithmetic rather than a literal.
        let rect = CropGeometry.fitted(.original, inside: CropGeometry.unitFrame, frame: CGSize(width: 64, height: 48))

        #expect(rect == CropGeometry.unitFrame)
        #expect(Crop(rect: rect, aspect: .original, rotation: .none).isIdentity)
    }

    @Test("It stays the whole photo even where the arithmetic does not come out exactly")
    func solverRoundingIsTolerated() {
        // The case the tolerance is for, and it is not rare: meeting a frame's own
        // ratio means multiplying by it and dividing back, and that round trip
        // misses one for 1228 of the 19321 frame sizes between 2×2 and 140×140 —
        // the count was measured, not guessed. 4000×2251 is one of them, and an
        // exact test would call picking "Original" on it an edit and render it as
        // one.
        let rect = CropGeometry.fitted(
            .original,
            inside: CropGeometry.unitFrame,
            frame: CGSize(width: 4000, height: 2251)
        )

        #expect(rect != CropGeometry.unitFrame, "This frame is only useful as a test while it misses")
        #expect(Crop(rect: rect, aspect: .original, rotation: .none).isIdentity)
    }

    @Test("A crop a hair short of the frame is the whole photo, wherever the hair came from")
    func aNearMissIsStillIdentity() {
        // Stated directly as well, because the solver's rounding is a fact about
        // the platform's arithmetic and this is a fact about the type.
        let rect = CGRect(x: 0, y: 1.1102230246251565e-16, width: 1, height: 0.9999999999999998)

        #expect(rect != CropGeometry.unitFrame)
        #expect(Crop(rect: rect, aspect: .original, rotation: .none).isIdentity)
    }

    @Test("Anything that takes pixels away, or turns the photo, is not the identity")
    func partialCropsAreNotIdentity() {
        #expect(Crop(rect: CGRect(x: 0, y: 0, width: 0.5, height: 1), aspect: .free, rotation: .none).isIdentity == false)
        #expect(Crop(rect: CropGeometry.unitFrame, aspect: .original, rotation: .clockwise).isIdentity == false)
        #expect(EditRecipe(crop: Crop(rect: CropGeometry.unitFrame, aspect: .original, rotation: .upsideDown)).isIdentity == false)
    }

    // MARK: - Ratios

    @Test("A ratio is its pair, however it was written down")
    func ratiosCompareByCrossMultiplying() {
        #expect(AspectRatio.fixed(width: 32, height: 18) == AspectRatio.fixed(width: 16, height: 9))
        #expect(AspectRatio.ratio(32, 18) == .fixed(width: 16, height: 9))
        #expect(AspectRatio.fixed(width: 16, height: 9) != AspectRatio.fixed(width: 9, height: 16))
    }

    @Test("The unconstrained shapes are not each other")
    func freeAndOriginalAreDifferent() {
        #expect(AspectRatio.free != AspectRatio.original)
        #expect(AspectRatio.free != AspectRatio.fixed(width: 1, height: 1))
        #expect(AspectRatio.original != AspectRatio.fixed(width: 1, height: 1))
    }

    @Test("A ratio that is written down backwards is reduced, and one built directly still compares")
    func ratiosAreReducedForReading() {
        // The panel reads this one back, so it has to be the pair the user
        // recognises rather than the pair they typed.
        #expect(AspectRatio.ratio(32, 18) == .fixed(width: 16, height: 9))
        #expect(AspectRatio.ratio(-16, 9) == .fixed(width: 16, height: 9))
        #expect(AspectRatio.ratio(0, 9) == .fixed(width: 1, height: 9))
    }

    @Test("Swapping turns a pair over, and leaves the unconstrained shapes alone")
    func swapping() {
        #expect(AspectRatio.fixed(width: 16, height: 9).swapped == .fixed(width: 9, height: 16))
        #expect(AspectRatio.fixed(width: 9, height: 16).swapped == .fixed(width: 16, height: 9))
        #expect(AspectRatio.free.swapped == .free)
        #expect(AspectRatio.original.swapped == .original)
    }

    @Test("A ratio is identified for a test to address it by")
    func ratioIdentifiers() {
        #expect(AspectRatio.free.identifier == "free")
        #expect(AspectRatio.original.identifier == "original")
        #expect(AspectRatio.fixed(width: 16, height: 9).identifier == "16x9")
    }

    @Test("The presets offer both orientations of the classic shapes")
    func presetsCoverBothOrientations() {
        #expect(AspectRatio.presets.contains(.free))
        #expect(AspectRatio.presets.contains(.fixed(width: 9, height: 16)))
        #expect(AspectRatio.presets.contains(.fixed(width: 4, height: 5)))
        #expect(AspectRatio.presets.contains(.fixed(width: 5, height: 4)))
        #expect(AspectRatio.presets.contains(.fixed(width: 2, height: 3)))
        #expect(AspectRatio.presets.contains(.fixed(width: 3, height: 2)))
        #expect(AspectRatio.presets.contains(.fixed(width: 3, height: 4)))
        #expect(AspectRatio.presets.contains(.fixed(width: 4, height: 3)))
        #expect(AspectRatio.presets.contains(.free))
        #expect(AspectRatio.presets.contains(.original))
    }

    // MARK: - Turning

    @Test("A quarter turn is undone by going back the other way")
    func turningIsReversible() {
        #expect(QuarterTurn.none.rotatedClockwise == .clockwise)
        #expect(QuarterTurn.counterclockwise.rotatedClockwise == .none)
        #expect(QuarterTurn.none.rotatedCounterclockwise == .counterclockwise)
        #expect(QuarterTurn.clockwise.rotatedCounterclockwise == .none)

        var turn = QuarterTurn.none
        for _ in 0..<4 { turn = turn.rotatedClockwise }
        #expect(turn == .none)
    }

    @Test("Only the quarter turns swap the frame's axes")
    func onlyQuarterTurnsSwapAxes() {
        #expect(QuarterTurn.none.swapsAxes == false)
        #expect(QuarterTurn.upsideDown.swapsAxes == false)
        #expect(QuarterTurn.clockwise.swapsAxes)
        #expect(QuarterTurn.counterclockwise.swapsAxes)
    }

    @Test("A turn is expressed as the orientation ImageIO and Core Image understand")
    func turnsHaveOrientations() {
        #expect(QuarterTurn.none.orientation == .up)
        #expect(QuarterTurn.clockwise.orientation == .right)
        #expect(QuarterTurn.upsideDown.orientation == .down)
        #expect(QuarterTurn.counterclockwise.orientation == .left)
    }

    // MARK: - Persistence

    @Test("A recipe survives a round trip through JSON")
    func recipeIsCodable() throws {
        let recipe = EditRecipe(
            crop: Crop(
                rect: CGRect(x: 0.125, y: 0.25, width: 0.5, height: 0.375),
                aspect: .fixed(width: 16, height: 9),
                rotation: .counterclockwise
            )
        )

        let data = try JSONEncoder().encode(recipe)
        let decoded = try JSONDecoder().decode(EditRecipe.self, from: data)

        #expect(decoded == recipe)
        #expect(decoded.crop.rect == recipe.crop.rect)
        #expect(decoded.crop.rotation == .counterclockwise)
    }

    @Test("Every shape of ratio survives a round trip, including a free one")
    func ratiosAreCodable() throws {
        for ratio in AspectRatio.presets + [.ratio(7, 5)] {
            let data = try JSONEncoder().encode(ratio)
            let decoded = try JSONDecoder().decode(AspectRatio.self, from: data)
            #expect(decoded == ratio, "\(ratio) did not come back")
        }
    }

    // MARK: - What the engine would draw

    @Test("Two recipes that differ only in the crop's shape are the same picture")
    func theCropShapeIsNotDrawn() {
        // `aspect` constrains a drag; it is not in the pixels. The canvas asks
        // this before rendering, because a panel closing over a crop nobody moved
        // asks for the picture that is already up — and the tool's own recipe for
        // the photo whole names a free crop where the committed one names the
        // photo's own shape.
        let whole = EditRecipe(crop: Crop(rect: CropGeometry.unitFrame, aspect: .free, rotation: .none))
        let same = EditRecipe(crop: Crop(rect: CropGeometry.unitFrame, aspect: .original, rotation: .none))

        #expect(whole != same, "They are not the same value, which is why this is asked separately")
        #expect(whole.rendersTheSame(as: same))
        #expect(same.rendersTheSame(as: whole))
    }

    @Test("A turn, a crop or a grade is a different picture")
    func everythingDrawnIsCompared() {
        let rect = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let base = EditRecipe(crop: Crop(rect: CropGeometry.unitFrame, aspect: .free, rotation: .none))
        let cropped = EditRecipe(crop: Crop(rect: rect, aspect: .free, rotation: .none))
        let turned = EditRecipe(crop: Crop(rect: CropGeometry.unitFrame, aspect: .free, rotation: .clockwise))

        var graded = ColorAdjustments()
        graded.saturation = 0.5
        let gradedRecipe = EditRecipe(crop: Crop(rect: CropGeometry.unitFrame, aspect: .free, rotation: .none), color: graded)

        #expect(!base.rendersTheSame(as: cropped))
        #expect(!base.rendersTheSame(as: turned))
        #expect(!base.rendersTheSame(as: gradedRecipe))
        #expect(base.rendersTheSame(as: base))
    }
}

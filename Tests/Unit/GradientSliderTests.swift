//
//  GradientSliderTests.swift
//  PhotonTests
//

import Foundation
import Testing

@testable import Photon

/// Where a slider's value sits, and what a point on its track asks for.
///
/// Small arithmetic, and it is the part of a hand-drawn control that a test can
/// hold: a bipolar slider that rested anywhere but in the middle, or one that
/// wrapped a drag past its end round to the other end, would look right and feel
/// wrong.
@Suite("Gradient slider")
@MainActor
struct GradientSliderTests {
    @Test("A slider that goes both ways rests in the middle")
    func theMiddleIsNeutral() {
        #expect(GradientSlider.position(of: 0, in: ColorAdjustments.range) == 0.5)
        #expect(GradientSlider.value(at: 0.5, in: ColorAdjustments.range) == 0)
    }

    @Test("A slider that only takes away rests at its left end")
    func theCastSliderRestsAtNothing() {
        #expect(GradientSlider.position(of: 0, in: ColorAdjustments.colorCastRange) == 0)
        #expect(GradientSlider.position(of: 1, in: ColorAdjustments.colorCastRange) == 1)
    }

    @Test("The ends of a range are the ends of the track")
    func theEndsMeet() {
        #expect(GradientSlider.position(of: -1, in: ColorAdjustments.range) == 0)
        #expect(GradientSlider.position(of: 1, in: ColorAdjustments.range) == 1)
        #expect(GradientSlider.value(at: 0, in: ColorAdjustments.range) == -1)
        #expect(GradientSlider.value(at: 1, in: ColorAdjustments.range) == 1)
    }

    @Test("A drag that runs off the end of a slider asks for its end, not for the other one")
    func draggingPastTheEndClamps() {
        #expect(GradientSlider.value(at: -3, in: ColorAdjustments.range) == -1)
        #expect(GradientSlider.value(at: 4, in: ColorAdjustments.range) == 1)
    }

    @Test("A value beyond the range is drawn at the end of the track rather than off it")
    func valuesOutsideTheRangeStillDraw() {
        #expect(GradientSlider.position(of: -2, in: ColorAdjustments.range) == 0)
        #expect(GradientSlider.position(of: 2, in: ColorAdjustments.range) == 1)
    }

    @Test("A point on the track is the value there, and back again")
    func positionAndValueAreInverses() {
        for step in 0...20 {
            let spot = Double(step) / 20
            let value = GradientSlider.value(at: spot, in: ColorAdjustments.range)

            #expect(abs(GradientSlider.position(of: value, in: ColorAdjustments.range) - spot) < 1e-9)
        }
    }
}

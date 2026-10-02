//
//  ColorAdjustmentsTests.swift
//  PhotonTests
//

import CoreGraphics
import Foundation
import Testing

@testable import Photon

/// The colour tool's value: which band answers for which hue, what counts as an
/// edit, and what a recipe written before the tool existed decodes to.
@Suite("Color adjustments")
struct ColorAdjustmentsTests {
    // MARK: - What counts as an edit

    @Test("A photo with nothing done to its colours is not an edit")
    func nothingIsNeutral() {
        #expect(ColorAdjustments.identity.isIdentity)
        #expect(ColorAdjustments().isIdentity)
        #expect(ColorAdjustments().hasBandShift == false)
    }

    @Test("Every slider on its own is an edit")
    func everySliderCounts() {
        var saturation = ColorAdjustments.identity
        saturation.saturation = 0.1

        var vibrance = ColorAdjustments.identity
        vibrance.vibrance = -0.1

        var cast = ColorAdjustments.identity
        cast.colorCast = 0.1

        var band = ColorAdjustments.identity
        band[.saturation, in: .yellow] = 0.39

        for adjustments in [saturation, vibrance, cast, band] {
            #expect(adjustments.isIdentity == false)
        }
    }

    @Test("A band returned to neutral stops counting as an edit")
    func aBandCanGoBack() {
        var adjustments = ColorAdjustments()
        adjustments[.hue, in: .blue] = 0.5
        #expect(adjustments.hasBandShift)

        adjustments[.hue, in: .blue] = 0

        #expect(adjustments.hasBandShift == false, "The entry a band leaves behind does not ask for anything")
        #expect(adjustments.isIdentity)
        #expect(adjustments.bands.isEmpty, "A band that says nothing should not be stored at all")
    }

    @Test("A band's three modes are three separate values")
    func theModesAreIndependent() {
        var adjustments = ColorAdjustments()
        adjustments[.hue, in: .green] = 0.2
        adjustments[.saturation, in: .green] = -0.4
        adjustments[.luminance, in: .green] = 0.6

        #expect(adjustments[.hue, in: .green] == 0.2)
        #expect(adjustments[.saturation, in: .green] == -0.4)
        #expect(adjustments[.luminance, in: .green] == 0.6)
        #expect(adjustments[.hue, in: .red] == 0, "A band nobody has touched reads as neutral")
    }

    // MARK: - Which band answers for which hue

    @Test("A hue at a band's centre is that band's alone")
    func aCentreBelongsToItsBand() {
        for band in ColorBand.allCases {
            let weights = weights(forHue: band.centre)

            #expect(weights.count == 1, "\(band.rawValue) shares its own centre with \(weights.keys)")
            #expect(weights[band] == 1)
        }
    }

    @Test("A hue between two bands is shared, in proportion")
    func theRampIsEven() {
        // Yellow sits at 60 and green at 120, so 90 is exactly between them.
        let weights = weights(forHue: 90)

        #expect(weights[.yellow] == 0.5)
        #expect(weights[.green] == 0.5)
        #expect(weights.count == 2)
    }

    @Test("The ramp closes the circle between the last band and the first")
    func theCircleCloses() {
        // Magenta is at 320 and red at 0 — which is to say at 360, going
        // forwards — so 350 is three quarters of the way from magenta to red.
        // Only those two are involved: there is nothing between them.
        //
        // Three quarters of the *way*, but not three quarters of the share: the
        // ramp is eased, so the far end of a span is worth less than a straight
        // line would make it, and the two still add up to one.
        let weights = weights(forHue: 350)

        #expect(weights[.red] == 0.84375)
        #expect(weights[.magenta] == 0.15625)
        #expect(weights.count == 2)
        #expect(abs(weights.values.reduce(0, +) - 1) < 1e-12)
    }

    @Test("Every hue is answered for, and never twice over")
    func theWeightsAreAPartitionOfUnity() {
        for step in 0..<720 {
            let hue = Double(step) / 2
            let weights = weights(forHue: hue)

            #expect(abs(weights.values.reduce(0, +) - 1) < 1e-9, "The bands add up to \(weights) at \(hue)°")
            #expect(weights.count <= 2, "More than two bands claim \(hue)°")
            for weight in weights.values {
                #expect(weight > 0 && weight <= 1)
            }
        }
    }

    @Test("A hue beyond either end of the circle is the hue it wraps to")
    func hueWrapsBothWays() {
        #expect(weights(forHue: 380) == weights(forHue: 20))
        #expect(weights(forHue: -40) == weights(forHue: 320))
    }

    // MARK: - Persistence

    @Test("The adjustments survive a round trip through JSON")
    func adjustmentsAreCodable() throws {
        var adjustments = ColorAdjustments()
        adjustments.saturation = 0.25
        adjustments.vibrance = -0.5
        adjustments.colorCast = 0.75
        adjustments[.saturation, in: .yellow] = 0.39
        adjustments[.luminance, in: .blue] = -0.2

        let data = try JSONEncoder().encode(adjustments)

        #expect(try JSONDecoder().decode(ColorAdjustments.self, from: data) == adjustments)
    }

    @Test("A band is stored under its own name")
    func bandsReadAsThePanelDoes() throws {
        var adjustments = ColorAdjustments()
        adjustments[.saturation, in: .yellow] = 0.39

        let json = String(decoding: try JSONEncoder().encode(adjustments), as: UTF8.self)

        #expect(json.contains("\"yellow\""), "A recipe should read as the panel does, got \(json)")
    }

    @Test("A recipe written before the colour tool existed decodes to the photo's own colours")
    func anOldRecipeDecodesNeutral() throws {
        // The shape of a recipe from before this tool: today's, with the colour
        // taken back out. Written by removing the key rather than by hand, so the
        // fixture cannot quietly drift away from what the encoder produces.
        let recipe = EditRecipe(
            crop: Crop(rect: CGRect(x: 0.25, y: 0, width: 0.5, height: 1), aspect: .free, rotation: .none)
        )

        var object = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(recipe)) as? [String: Any]
        )
        #expect(object["color"] != nil, "The recipe no longer stores its colour under that name")
        object.removeValue(forKey: "color")

        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(EditRecipe.self, from: legacy)

        #expect(decoded.color.isIdentity, "A crop-only recipe asks for the photo's own colours")
        #expect(decoded.crop.rect == recipe.crop.rect)
    }
}

/// Which bands answer for a hue, and with how much of it.
///
/// A dictionary because these tests are about *which* bands are involved as much
/// as how much each gets: a hue between two centres has exactly two entries, and
/// one on a centre has exactly one. Bands that answer for none of it are left
/// out, which is what makes those counts say anything.
private func weights(forHue degrees: Double) -> [ColorBand: Double] {
    var weights: [ColorBand: Double] = [:]
    for band in ColorBand.allCases {
        let weight = ColorBand.weight(of: band, at: degrees)
        if weight != 0 { weights[band] = weight }
    }
    return weights
}

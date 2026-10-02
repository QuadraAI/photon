//
//  ColourSliderSnapshotTests.swift
//  PhotonTests
//

import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import Photon

/// What the colour panel's sliders look like.
///
/// `GradientSlider` is a control drawn rather than borrowed — a track, a fill, a
/// glow and a thumb, four shapes and a gradient that nothing else in the suite
/// looks at. Its arithmetic is covered by `GradientSliderTests`; this is the part
/// arithmetic cannot see, which is whether the thing on screen is the thing that
/// was intended.
@Suite("Colour slider snapshots")
@MainActor
struct ColourSliderSnapshotTests {
    private static let size = CGSize(width: 220, height: 24)

    /// A band's saturation slider, part way up, in the shape the panel draws it.
    private var slider: some View {
        GradientSlider(
            value: .constant(0.35),
            range: ColorAdjustments.range,
            neutral: 0,
            tint: ColorBand.cyan.color,
            ramp: HSLChannel.saturation.ramp(for: .cyan),
            label: Text(ColorBand.cyan.name),
            step: 0.01,
            identifier: "tool.color.band.cyan.saturation",
            onCommit: {}
        )
        .padding(.horizontal, 8)
        .background(.background)
    }

    @Test("A band's slider is drawn as it was agreed to look")
    func theSaturationSliderLooksAsAgreed() throws {
        try Snapshot.expect(slider, named: "colour-slider-saturation", size: Self.size)
    }

    /// The same control in the mode whose track runs black to white, so a change
    /// in the ramp or the tint is caught as well as a change in the shapes.
    private var luminanceSlider: some View {
        GradientSlider(
            value: .constant(-0.6),
            range: ColorAdjustments.range,
            neutral: 0,
            tint: ColorBand.green.color,
            ramp: HSLChannel.luminance.ramp(for: .green),
            label: Text(ColorBand.green.name),
            step: 0.01,
            identifier: "tool.color.band.green.luminance",
            onCommit: {}
        )
        .padding(.horizontal, 8)
        .background(.background)
    }

    @Test("A slider below neutral fills the other way, and is drawn as such")
    func theLuminanceSliderLooksAsAgreed() throws {
        try Snapshot.expect(luminanceSlider, named: "colour-slider-luminance", size: Self.size)
    }
}

//
//  RenderedPhoto.swift
//  Photon
//

import CoreGraphics

/// A photo the engine has rendered, at the size the canvas will draw it.
///
/// Carries the recipe's result *and* the photo without it: the crop overlay works
/// over the whole frame — a handle has to be draggable back out past the crop that
/// is there — and re-decoding it every time the crop tool opens would put a decode
/// in the middle of a click.
nonisolated struct RenderedPhoto: Sendable {
    /// The photo with the recipe applied.
    let image: CGImage

    /// The photo with nothing cropped from it, at the same size. Identical to
    /// ``image`` when the recipe is not an edit at all.
    let base: CGImage

    /// The photo's own pixel size, upright, as the file records it.
    ///
    /// The crop maths works in this, not in the preview's size: turning a
    /// normalized rect into pixels at preview size would give a different crop on
    /// export than the one the user dragged.
    let sourceSize: CGSize
}

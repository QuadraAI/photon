//
//  RenderedPhoto.swift
//  Photon
//

import CoreGraphics

/// A photo the engine has rendered, at the size the canvas will draw it.
///
/// Carries the recipe's result *and* the file's own pixels: the crop overlay works
/// over the whole frame — a handle has to be draggable back out past the crop that
/// is there — and re-decoding it every time the crop tool opens would put a decode
/// in the middle of a click.
nonisolated struct RenderedPhoto: Sendable {
    /// The photo with the recipe applied.
    let image: CGImage

    /// The file's own pixels, at the same size: nothing cropped from the photo
    /// and none of the colour tool's work on it.
    ///
    /// The canvas falls back to this while the crop overlay is open and there is
    /// nothing graded to draw instead. A photo that *has* been graded is shown
    /// from ``EditorViewModel/sessionBase``, which carries the colour as well as
    /// the turn — a crop has to be dragged over the picture the user is looking
    /// at, not over the one that came out of the camera.
    let base: CGImage

    /// The photo's own pixel size, upright, as the file records it.
    ///
    /// The crop maths works in this, not in the preview's size: turning a
    /// normalized rect into pixels at preview size would give a different crop on
    /// export than the one the user dragged.
    let sourceSize: CGSize
}

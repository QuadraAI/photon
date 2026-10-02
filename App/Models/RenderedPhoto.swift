//
//  RenderedPhoto.swift
//  Photon
//

import CoreGraphics
import CoreImage

/// A photo the engine has staged, at the size the canvas will draw it.
///
/// Carries the recipe's result *and* the file's own pixels: the crop overlay works
/// over the whole frame — a handle has to be draggable back out past the crop that
/// is there — and re-decoding it every time the crop tool opens would put a decode
/// in the middle of a click.
///
/// `CIImage` rather than `CGImage` because a preview is drawn rather than read:
/// Core Image's own description of a picture can be handed to a Metal view and
/// drawn on the GPU it was built on, where pixels would have to be copied off
/// that GPU and uploaded again on every frame of a slider drag.
nonisolated struct RenderedPhoto: Sendable {
    /// The photo with the recipe applied.
    let image: CIImage

    /// The file's own pixels: nothing cropped from the photo, and none of the
    /// colour tool's work on it.
    ///
    /// The canvas falls back to this while the crop overlay is open and there is
    /// nothing graded to draw instead. A photo that *has* been graded is shown
    /// from ``EditorViewModel/sessionBase``, which carries the colour as well as
    /// the turn — a crop has to be dragged over the picture the user is looking
    /// at, not over the one that came out of the camera.
    let base: CIImage

    /// The photo's own pixel size, upright, as the file records it.
    ///
    /// The crop maths works in this, not in the preview's size: turning a
    /// normalized rect into pixels at preview size would give a different crop on
    /// export than the one the user dragged.
    let sourceSize: CGSize

    /// The shape the picture is drawn at, which is what the canvas lays it out by.
    var pixelSize: CGSize { image.extent.size }
}

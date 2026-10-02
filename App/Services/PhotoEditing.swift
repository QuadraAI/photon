//
//  PhotoEditing.swift
//  Photon
//

import CoreGraphics
import Foundation

/// Turns a photo and a recipe into pixels.
///
/// The whole of editing goes through here. A tool never touches an image: it
/// produces a new ``EditRecipe``, and this renders it — which is what keeps an
/// edit re-editable, since the file is only ever read.
nonisolated protocol PhotoEditing: Sendable {
    /// The preview the file already carries inside it, decoded as it is.
    ///
    /// About a millisecond, and the reason a click puts a picture on the canvas
    /// at once instead of after a decode. It has no recipe applied, so it stands
    /// in for an unedited photo and nothing else.
    ///
    /// - Throws: ``PhotoRenderError/unreadable`` when the file cannot be read.
    func draft(for url: URL, maxPixelSize: Int) async throws(PhotoRenderError) -> CGImage

    /// The photo with `recipe` applied.
    ///
    /// - Parameter maxPixelSize: The longest edge of the result, or nil for the
    ///   photo at its own resolution. Preview and export are this same call with
    ///   a different number, which is what makes "what you see is what you get"
    ///   something a test holds the engine to rather than a claim.
    func render(_ url: URL, recipe: EditRecipe, maxPixelSize: Int?) async throws(PhotoRenderError) -> CGImage

    /// The photo's own pixel size, upright, read without decoding it.
    ///
    /// The crop maths needs the real size: holding a normalized rect to a ratio
    /// at the preview's size would give a different crop on export than the one
    /// the user dragged.
    func pixelSize(of url: URL) async throws(PhotoRenderError) -> CGSize
}

//
//  PhotoEditing.swift
//  Photon
//

import CoreGraphics
import CoreImage
import Foundation

/// Turns a photo and a recipe into pixels.
///
/// The whole of editing goes through here. A tool never touches an image: it
/// produces a new ``EditRecipe``, and this renders it — which is what keeps an
/// edit re-editable, since the file is only ever read.
nonisolated protocol PhotoEditing: Sendable {
    /// The context every preview is staged with.
    ///
    /// Whoever draws one has to draw it with this: a second context would
    /// compile the same kernels again, and would have none of the first one's
    /// cached intermediates to build on.
    var context: CIContext { get }

    /// The preview the file already carries inside it, decoded as it is.
    ///
    /// About a millisecond, and the reason a click puts a picture on the canvas
    /// at once instead of after a decode. It has no recipe applied, so it stands
    /// in for an unedited photo and nothing else.
    ///
    /// - Throws: ``PhotoRenderError/unreadable`` when the file cannot be read.
    func draft(for url: URL, maxPixelSize: Int) async throws(PhotoRenderError) -> CGImage

    /// The photo with `recipe` applied, left as something to draw.
    ///
    /// What the canvas is handed. A `CIImage` is a description rather than
    /// pixels, so nothing has been rendered yet and nothing has crossed back to
    /// the CPU: the view draws it on the GPU it was built on. Asking for the
    /// pixels instead — which is what ``render(_:recipe:maxPixelSize:)`` does —
    /// costs a wait for the GPU and a copy of the whole picture per frame, which
    /// is the difference between a slider that follows the pointer and one that
    /// arrives after it.
    func preview(_ url: URL, recipe: EditRecipe, maxPixelSize: Int?) async throws(PhotoRenderError) -> CIImage

    /// The photo with `recipe` applied, as pixels.
    ///
    /// - Parameter maxPixelSize: The longest edge of the result, or nil for the
    ///   photo at its own resolution. Preview and export are the same pipeline
    ///   with a different number, which is what makes "what you see is what you
    ///   get" something a test holds the engine to rather than a claim.
    func render(_ url: URL, recipe: EditRecipe, maxPixelSize: Int?) async throws(PhotoRenderError) -> CGImage

    /// The photo's own pixel size, upright, read without decoding it.
    ///
    /// The crop maths needs the real size: holding a normalized rect to a ratio
    /// at the preview's size would give a different crop on export than the one
    /// the user dragged.
    func pixelSize(of url: URL) async throws(PhotoRenderError) -> CGSize
}

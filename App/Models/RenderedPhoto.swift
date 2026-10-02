//
//  RenderedPhoto.swift
//  Photon
//

import CoreImage

/// The picture the canvas is drawing.
///
/// One picture, and nothing else. It used to carry the file's own pixels as well,
/// as a standby for while the crop tool was open, and the two could disagree about
/// what the user was looking at: the standby is *ungraded*, so opening the crop
/// tool over a grade showed the photo as it arrived until the graded picture was
/// ready — a flash of the wrong picture at the moment the user asked to look
/// closely at the right one.
///
/// Which picture this is is the view model's business, not the canvas's: the view
/// draws what it is handed.
///
/// `CIImage` rather than `CGImage` because a preview is drawn rather than read:
/// Core Image's own description of a picture can be handed to a Metal view and
/// drawn on the GPU it was built on, where pixels would have to be copied off
/// that GPU and uploaded again on every frame of a slider drag.
nonisolated struct RenderedPhoto: Sendable {
    /// The picture to draw, as the engine staged it.
    let image: CIImage

    /// What the picture was made from.
    ///
    /// Kept with the picture because it is what makes "show this" cost nothing
    /// when the canvas is already showing it: every move that can change the
    /// picture comes through one refresh, and most of them — closing a panel,
    /// cancelling a crop, committing a drag that ended where it started — ask for
    /// the picture that is already up.
    let recipe: EditRecipe
}

/// The photo as the file gave it to us.
///
/// Two facts that do not change while the photo is selected: its own pixels,
/// whole and ungraded, and the size the crop maths works in. Held beside the
/// canvas's picture rather than inside it, because the picture changes with the
/// tool in hand and these do not — and because the file's own pixels are what the
/// crop overlay sits on when there is nothing turned and nothing graded, so
/// keeping them is what makes opening the crop tool cost no decode at all.
nonisolated struct DecodedPhoto: Sendable {
    /// The file's own pixels: nothing cropped from the photo, and none of the
    /// colour tool's work on it.
    let base: CIImage

    /// The photo's own pixel size, upright, as the file records it.
    ///
    /// The crop maths works in this, not in the preview's size: turning a
    /// normalized rect into pixels at preview size would give a different crop on
    /// export than the one the user dragged.
    let sourceSize: CGSize
}

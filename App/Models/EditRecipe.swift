//
//  EditRecipe.swift
//  Photon
//

/// Everything that has been done to a photo, as a value.
///
/// The photo's current look, not how it got there. Applying it to the file is the
/// whole of editing and storing it beside the photo is the whole of saving, which
/// is what makes every tool non-destructive. `Codable` from the first tool rather
/// than when persistence lands, so a recipe written today decodes tomorrow.
nonisolated struct EditRecipe: Equatable, Sendable, Codable {
    var crop: Crop

    /// The photo with nothing done to it.
    static let identity = EditRecipe(crop: .identity)

    /// Whether this recipe asks for the file's own pixels, whole.
    var isIdentity: Bool { crop.isIdentity }
}

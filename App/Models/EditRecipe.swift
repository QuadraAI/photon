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

    /// What the colour tool has been told to do. Held apart from ``crop``
    /// because the two are different kinds of edit, and because the panels that
    /// make them open and close independently.
    var color: ColorAdjustments = .identity

    /// The photo with nothing done to it.
    static let identity = EditRecipe(crop: .identity)

    init(crop: Crop, color: ColorAdjustments = .identity) {
        self.crop = crop
        self.color = color
    }

    /// Decodes a recipe, tolerating one written before the colour tool existed.
    ///
    /// The whole point of storing recipes as values is that one written today is
    /// read tomorrow, and a crop-only recipe is exactly that case: it has no
    /// colour to read, which means it asked for the photo's own.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        crop = try container.decode(Crop.self, forKey: .crop)
        color = try container.decodeIfPresent(ColorAdjustments.self, forKey: .color) ?? .identity
    }

    /// Whether this recipe asks for the file's own pixels, whole.
    var isIdentity: Bool { crop.isIdentity && color.isIdentity }

    /// Whether this recipe asks for the same picture as `other`.
    ///
    /// The rect, the turn and the colours are what the engine renders;
    /// ``Crop/aspect`` only constrains a drag, so two recipes that differ in it
    /// are the same picture. That is what lets the canvas tell whether the picture
    /// it is showing is the one being asked for — a panel closing over a crop
    /// nobody moved asks for the picture that is already up, and rendering it
    /// again is a frame of work for no frame of difference.
    func rendersTheSame(as other: EditRecipe) -> Bool {
        crop.rect == other.crop.rect
            && crop.rotation == other.crop.rotation
            && color == other.color
    }
}

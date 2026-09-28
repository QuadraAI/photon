//
//  PhotoItem+Presentation.swift
//  Photon
//

import Foundation
import UniformTypeIdentifiers

extension PhotoItem {
    /// SF Symbol for the file's kind.
    ///
    /// A two-way distinction on purpose: whether a file needs the RAW pipeline
    /// is the one difference that changes what Photon can do with it. It is a
    /// glyph for the *kind*, never a preview of the picture.
    var symbolName: String {
        contentType?.conforms(to: .rawImage) == true ? "camera.aperture" : "photo"
    }
}

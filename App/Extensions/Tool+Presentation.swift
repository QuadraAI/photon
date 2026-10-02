//
//  Tool+Presentation.swift
//  Photon
//

import SwiftUI

extension Tool {
    /// Shown as the panel's heading, and as the rail icon's accessibility label.
    ///
    /// A ``LocalizedStringKey`` rather than a `String` so it re-renders in the
    /// newly picked language the moment it changes.
    var name: LocalizedStringKey {
        switch self {
        case .crop: "tool.crop"
        case .light: "tool.light"
        case .color: "tool.color"
        case .presets: "tool.presets"
        }
    }

    /// SF Symbol for the rail.
    ///
    /// The colour tool wears the details tool's filters, which is where the
    /// merged tool's icon came from: two overlapping discs say "adjust colour"
    /// better than a palette did, and it is the icon the rail already had.
    var symbolName: String {
        switch self {
        case .crop: "crop.rotate"
        case .light: "sun.max"
        case .color: "camera.filters"
        case .presets: "wand.and.stars"
        }
    }
}

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
        case .details: "tool.details"
        case .presets: "tool.presets"
        }
    }

    /// SF Symbol for the rail.
    var symbolName: String {
        switch self {
        case .crop: "crop.rotate"
        case .light: "sun.max"
        case .color: "paintpalette"
        case .details: "camera.filters"
        case .presets: "wand.and.stars"
        }
    }
}

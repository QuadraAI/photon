//
//  Tool.swift
//  Photon
//

import Foundation

/// A tool in the editor's right-hand rail.
///
/// The rail shows icons only; opening one reveals a panel beside it. Light and
/// Presets are still placeholders; the crop and colour tools are real.
nonisolated enum Tool: String, CaseIterable, Identifiable, Sendable {
    case crop
    case light
    /// Colour and the detail work that reads as colour: one tool, because a
    /// photograph is graded and sharpened in the same breath and two icons
    /// between Crop and Presets only made the rail longer.
    case color
    case presets

    var id: Self { self }
}

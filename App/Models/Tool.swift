//
//  Tool.swift
//  Photon
//

import Foundation

/// A tool in the editor's right-hand rail.
///
/// The rail shows icons only; opening one reveals a panel beside it. The tools
/// themselves arrive with the render pipeline, so the panels are placeholders
/// for now.
nonisolated enum Tool: String, CaseIterable, Identifiable, Sendable {
    case crop
    case light
    case color
    case details
    case presets

    var id: Self { self }
}

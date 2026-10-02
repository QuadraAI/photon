//
//  EditStepName+Presentation.swift
//  Photon
//

import SwiftUI

extension EditStepName {
    /// What the step reads as, wherever it is named.
    ///
    /// A `Text` rather than a `LocalizedStringKey`, because the name is built
    /// from two pieces and both have to resolve against the language that is on
    /// screen when they are drawn — not the one that was on when the step was
    /// recorded. Building a `String` anywhere along the way would freeze it.
    var text: Text {
        switch self {
        case .original:
            Text("editor.history.original")
        case .reset:
            Text("editor.history.reset")
        case .crop(nil):
            Text("editor.history.crop")
        case .crop(.some(let ratio)):
            Text("editor.history.crop.ratio \(ratio.text)")
        case .rotate(let turn):
            switch turn {
            case .none: Text("editor.history.rotate")
            case .clockwise: Text("editor.history.rotate.right")
            case .counterclockwise: Text("editor.history.rotate.left")
            case .upsideDown: Text("editor.history.rotate.half")
            }
        case .color(let change):
            // The panel's own labels, which is the point: the menu says "Undo
            // Saturation" because that is what the slider the user moved is
            // called, not because a second set of names agrees with it.
            switch change {
            case .saturation, .bandSaturation: Text("tool.color.saturation")
            case .vibrance: Text("tool.color.vibrance")
            case .colorCast: Text("tool.color.colorCast")
            case .hue: Text("tool.color.channel.hue")
            case .luminance: Text("tool.color.channel.luminance")
            case .all: Text("tool.color")
            }
        }
    }

    /// The Edit menu's title for taking this step back: "Undo Crop 16:9".
    ///
    /// Naming the step rather than saying "Undo" is what makes a history the user
    /// cannot see yet still legible: the button says what it is about to do
    /// before it is pressed.
    var undoTitle: Text { Text("editor.undo.named \(text)") }

    /// The Edit menu's title for making this step again: "Redo Crop 16:9".
    var redoTitle: Text { Text("editor.redo.named \(text)") }
}

//
//  AspectRatio+Presentation.swift
//  Photon
//

import SwiftUI

extension AspectRatio {
    /// What the ratio reads as in the crop panel.
    ///
    /// A `Text` rather than a `LocalizedStringKey` so it composes: it is
    /// interpolated into the names of the history steps it produced, and both
    /// halves have to resolve against the language on screen when they are drawn
    /// rather than the one that was on when the step was recorded.
    var text: Text {
        switch self {
        case .free:
            Text("tool.crop.ratio.free")
        case .original:
            Text("tool.crop.ratio.original")
        case .fixed(let width, let height):
            // A pair of numbers is its own name in every language, and there is
            // no key for "16:9" — so it is drawn rather than looked up. Built
            // from a `String` on purpose: interpolating into a key here would
            // make the catalog key `"%lld:%lld"`.
            Text(verbatim: "\(width):\(height)")
        }
    }

    /// A stable name for a control to be addressed by, which a ratio's own text
    /// cannot be — "16:9" contains a colon, and `free` and `original` are words
    /// that change with the language.
    var identifier: String {
        switch self {
        case .free: "free"
        case .original: "original"
        case .fixed(let width, let height): "\(width)x\(height)"
        }
    }
}
